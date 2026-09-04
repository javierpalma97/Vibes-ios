import Foundation
import SwiftData
import Combine

@MainActor
class LibraryManager: ObservableObject {
    static let shared = LibraryManager()

    @Published var likedSongs: [Song] = []
    @Published var playlists: [Playlist] = []
    @Published var recentlyPlayed: [Song] = []
    @Published var searchHistory: [SearchHistory] = []
    @Published var quickPicks: [Song] = []

    private let ytMusic = YouTubeMusic.shared
    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context

        // Load data asynchronously to avoid blocking UI on startup
        Task { @MainActor in
            await loadLocalData()
        }
    }

    func deleteAllData() {
        guard let context = modelContext else { return }
        let types: [any PersistentModel.Type] = [Song.self, Album.self, Artist.self, Playlist.self, PlaylistSongMap.self, Format.self, SearchHistory.self, PlayEvent.self, Lyrics.self]
        for t in types {
            do {
                try context.delete(model: t)
            } catch {
                print("⚠️ deleteAllData \(t) failed: \(error)")
            }
        }
        try? context.save()
        likedSongs = []
        playlists = []
        recentlyPlayed = []
        searchHistory = []
        quickPicks = []
    }

    func clearSearchHistoryData() {
        guard let context = modelContext else { return }
        do {
            try context.delete(model: SearchHistory.self)
            try context.save()
            searchHistory = []
        } catch {
            print("⚠️ clearSearchHistoryData failed: \(error)")
        }
    }

    // MARK: - Local Data Loading

    private func loadLocalData() async {
        guard let context = modelContext else { return }

        // Load liked songs
        let likedDescriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.liked == true },
            sortBy: [SortDescriptor(\.dateModified, order: .reverse)]
        )

        if let songs = try? context.fetch(likedDescriptor) {
            likedSongs = songs
            print("📚 [LibraryManager] Loaded \(songs.count) liked songs")
        }

        // Load playlists
        let playlistDescriptor = FetchDescriptor<Playlist>(
            sortBy: [SortDescriptor(\.dateModified, order: .reverse)]
        )

        if let playlists = try? context.fetch(playlistDescriptor) {
            self.playlists = playlists
            print("📚 [LibraryManager] Loaded \(playlists.count) playlists")
        }

        // Load recently played
        var recentDescriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.playCount > 0 },
            sortBy: [SortDescriptor(\.dateModified, order: .reverse)]
        )
        recentDescriptor.fetchLimit = 50

        if let songs = try? context.fetch(recentDescriptor) {
            recentlyPlayed = songs
            print("📚 [LibraryManager] Loaded \(songs.count) recently played songs")
        }

        // Load search history
        var historyDescriptor = FetchDescriptor<SearchHistory>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        historyDescriptor.fetchLimit = 20

        if let history = try? context.fetch(historyDescriptor) {
            searchHistory = history
        }

        // Load quick picks (matching Android implementation)
        quickPicks = await getQuickPicks()
        print("📚 [LibraryManager] Loaded \(quickPicks.count) quick picks")
    }

    func clearSearchHistory() {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<SearchHistory>()
        if let history = try? context.fetch(descriptor) {
            for item in history {
                context.delete(item)
            }
            try? context.save()
        }

        searchHistory = []
    }

    // MARK: - Sync with YouTube Music

    func syncLibrary() async throws {
        guard let context = modelContext else {
            print("⚠️ [LibraryManager] No model context for sync")
            await MainActor.run { DebugLogger.shared.log("⚠️ sync no ModelContext") }
            return
        }

        print("🔄 [LibraryManager] Starting library sync...")
        await MainActor.run { DebugLogger.shared.log("🔄 sync start isAuth=\(InnerTubeClient.shared.isAuthenticated) \(InnerTubeClient.shared.debugAuthState)") }

        // Sync liked songs (batch mode to avoid reloading after each song)
        do {
            await MainActor.run { DebugLogger.shared.log("📥 getLikedSongs start") }
            let ytLikedSongs = try await ytMusic.getLikedSongs()
            print("📥 [LibraryManager] Syncing \(ytLikedSongs.count) liked songs...")
            await MainActor.run { DebugLogger.shared.log("✅ getLikedSongs \(ytLikedSongs.count)") }
            for ytSong in ytLikedSongs {
                await saveSong(ytSong, liked: true, skipReload: true)
            }
            print("✅ [LibraryManager] Synced \(ytLikedSongs.count) liked songs")
        } catch {
            print("❌ [LibraryManager] Failed to sync liked songs: \(error)")
            await MainActor.run { DebugLogger.shared.log("❌ getLikedSongs \(error)") }
            throw error
        }

        // Sync playlists (batch mode to avoid reloading after each playlist)
        do {
            var ytPlaylists = try await ytMusic.getLibraryPlaylists()
            print("📥 [LibraryManager] Syncing \(ytPlaylists.count) playlists...")
            await MainActor.run { DebugLogger.shared.log("📥 getLibraryPlaylists \(ytPlaylists.count)") }
            // Fallback para cuentas con 1 sola lista creada por el usuario (a veces viene en carousel, no grid)
            if ytPlaylists.isEmpty {
                do {
                    let alt = try await ytMusic.getAccountPlaylists()
                    print("📚 [LibraryManager] Fallback getAccountPlaylists \(alt.count)")
                    await MainActor.run { DebugLogger.shared.log("📚 fallback accountPlaylists \(alt.count)") }
                    ytPlaylists = alt
                } catch {
                    print("⚠️ [LibraryManager] Fallback failed \(error)")
                }
            }
            for ytPlaylist in ytPlaylists {
                await savePlaylist(ytPlaylist, skipReload: true)
            }
            print("✅ [LibraryManager] Synced \(ytPlaylists.count) playlists")
        } catch {
            print("❌ [LibraryManager] Failed to sync playlists: \(error)")
            await MainActor.run { DebugLogger.shared.log("❌ getLibraryPlaylists \(error)") }
            // Don't throw - partial sync is okay
        }

        // Sync albums
        do {
            let ytAlbums = try await ytMusic.getLibraryAlbums()
            print("📥 [LibraryManager] Syncing \(ytAlbums.count) albums...")
            await MainActor.run { DebugLogger.shared.log("📥 getLibraryAlbums \(ytAlbums.count)") }
            for ytAlbum in ytAlbums {
                await saveAlbum(ytAlbum, skipReload: true)
            }
            print("✅ [LibraryManager] Synced \(ytAlbums.count) albums")
        } catch {
            print("⚠️ [LibraryManager] Failed to sync albums: \(error)")
        }

        // Sync artists
        do {
            let ytArtists = try await ytMusic.getLibraryArtists()
            print("📥 [LibraryManager] Syncing \(ytArtists.count) artists...")
            await MainActor.run { DebugLogger.shared.log("📥 getLibraryArtists \(ytArtists.count)") }
            for ytArtist in ytArtists {
                await saveArtist(ytArtist, skipReload: true)
            }
            print("✅ [LibraryManager] Synced \(ytArtists.count) artists")
        } catch {
            print("⚠️ [LibraryManager] Failed to sync artists: \(error)")
        }

        // Reload local data once at the end
        print("🔄 [LibraryManager] Reloading library data...")
        await loadLocalData()
        print("✅ [LibraryManager] Library sync complete")
    }

    func saveAlbum(_ ytAlbum: YTAlbum, skipReload: Bool = false) async {
        guard let context = modelContext else { return }

        let albumId = ytAlbum.id
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate<Album> { album in
                album.id == albumId
            }
        )

        let existing = try? context.fetch(descriptor).first
        if let existing = existing {
            existing.title = ytAlbum.title
            existing.artistsText = ytAlbum.artists
            existing.thumbnailUrl = ytAlbum.thumbnailUrl
        } else {
            let album = Album(
                id: ytAlbum.id,
                title: ytAlbum.title,
                artistsText: ytAlbum.artists,
                year: ytAlbum.year,
                thumbnailUrl: ytAlbum.thumbnailUrl,
                liked: true
            )
            context.insert(album)
        }

        try? context.save()
        if !skipReload {
            await loadLocalData()
        }
    }

    func saveArtist(_ ytArtist: YTArtist, skipReload: Bool = false) async {
        guard let context = modelContext else { return }

        let artistId = ytArtist.id
        let descriptor = FetchDescriptor<Artist>(
            predicate: #Predicate<Artist> { artist in
                artist.id == artistId
            }
        )

        let existing = try? context.fetch(descriptor).first
        if let existing = existing {
            existing.name = ytArtist.name
            existing.thumbnailUrl = ytArtist.thumbnailUrl
        } else {
            let artist = Artist(
                id: ytArtist.id,
                name: ytArtist.name,
                thumbnailUrl: ytArtist.thumbnailUrl,
                isSubscribed: true
            )
            context.insert(artist)
        }

        try? context.save()
        if !skipReload {
            await loadLocalData()
        }
    }

    // MARK: - Song Management

    func saveSong(_ ytSong: YTSong, liked: Bool = false, skipReload: Bool = false) async {
        guard let context = modelContext else {
            print("⚠️ [LibraryManager] No model context available")
            return
        }

        // Check if song already exists
        let songId = ytSong.id
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { song in
                song.id == songId
            }
        )

        let existingSong = try? context.fetch(descriptor).first

        if let existing = existingSong {
            // Update existing song - preserve liked status if explicitly set
            if liked {
                existing.liked = true
            }
            existing.dateModified = Date()

            // Update metadata if provided
            if let thumbnailUrl = ytSong.thumbnailUrl, !thumbnailUrl.isEmpty {
                existing.thumbnailUrl = thumbnailUrl
            }
            if let albumId = ytSong.albumId, !albumId.isEmpty {
                existing.albumId = albumId
            }
            if let albumName = ytSong.albumName, !albumName.isEmpty {
                existing.albumName = albumName
            }
        } else {
            // Create new song
            let song = Song(
                id: ytSong.id,
                title: ytSong.title,
                artistsText: ytSong.artists,
                durationText: ytSong.duration,
                thumbnailUrl: ytSong.thumbnailUrl,
                albumId: ytSong.albumId,
                albumName: ytSong.albumName,
                liked: liked
            )

            context.insert(song)
        }

        do {
            try context.save()
        } catch {
            print("❌ [LibraryManager] Failed to save song \(ytSong.title): \(error)")
        }

        // Only reload if not in batch mode
        if !skipReload {
            await loadLocalData()
        }
    }

    func getSong(id: String) async -> Song? {
        guard let context = modelContext else {
            return nil
        }

        let songId = id
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { song in
                song.id == songId
            }
        )

        do {
            let results = try context.fetch(descriptor)
            if let song = results.first {
                return song
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }

    func deleteSong(_ song: Song) async {
        guard let context = modelContext else {
            return
        }

        context.delete(song)

        do {
            try context.save()
        } catch {
            // Silently fail
        }

        await loadLocalData()
    }

    func toggleLike(song: Song) async {
        song.liked.toggle()
        song.dateModified = Date()

        if let context = modelContext {
            try? context.save()
        }

        // Sync with YouTube Music
        do {
            if song.liked {
                try await ytMusic.likeSong(videoId: song.id)
            } else {
                try await ytMusic.unlikeSong(videoId: song.id)
            }
        } catch {
            // Revert on failure
            song.liked.toggle()
        }

        await loadLocalData()
    }

    func updateSongLikedStatus(_ song: Song, isLiked: Bool) async {
        song.liked = isLiked
        song.dateModified = Date()

        if let context = modelContext {
            try? context.save()
        }

        await loadLocalData()
    }

    func incrementPlayCount(song: Song, playTime: Int) {
        song.playCount += 1
        song.totalPlayTime += playTime
        song.dateModified = Date()

        if let context = modelContext {
            try? context.save()
        }

        Task {
            await loadLocalData()
        }
    }

    // MARK: - Playlist Management

    func savePlaylist(_ ytPlaylist: YTPlaylist, skipReload: Bool = false) async {
        guard let context = modelContext else { return }

        let playlistId = ytPlaylist.id
        let descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate<Playlist> { p in
                p.id == playlistId
            }
        )

        let existing = try? context.fetch(descriptor).first

        if let existing = existing {
            existing.name = ytPlaylist.name
            existing.thumbnailUrl = ytPlaylist.thumbnailUrl
            existing.songCount = ytPlaylist.songCount
            existing.dateModified = Date()
        } else {
            let playlist = Playlist(
                id: ytPlaylist.id,
                name: ytPlaylist.name,
                thumbnailUrl: ytPlaylist.thumbnailUrl,
                playlistType: .youtube,
                songCount: ytPlaylist.songCount,
                browseId: ytPlaylist.id,
                author: ytPlaylist.author
            )

            context.insert(playlist)
        }

        do {
            try context.save()
        } catch {
            print("❌ [LibraryManager] Failed to save playlist \(ytPlaylist.name): \(error)")
        }

        // Only reload if not in batch mode
        if !skipReload {
            await loadLocalData()
        }
    }

    func createLocalPlaylist(name: String) async -> Playlist {
        guard let context = modelContext else {
            fatalError("ModelContext not set")
        }

        let playlist = Playlist(
            id: UUID().uuidString,
            name: name,
            playlistType: .local,
            isEditable: true
        )

        context.insert(playlist)
        try? context.save()

        await loadLocalData()
        return playlist
    }

    func deletePlaylist(_ playlist: Playlist) async {
        guard let context = modelContext else { return }

        context.delete(playlist)
        try? context.save()

        await loadLocalData()
    }

    func addSongToPlaylist(_ song: Song, playlist: Playlist) async {
        guard let context = modelContext else { return }

        let position = playlist.items?.count ?? 0
        let map = PlaylistSongMap(
            id: UUID().uuidString,
            playlistId: playlist.id,
            songId: song.id,
            position: position
        )

        map.song = song
        map.playlist = playlist

        context.insert(map)

        playlist.songCount += 1
        playlist.dateModified = Date()

        try? context.save()
        await loadLocalData()
    }

    func removeSongFromPlaylist(mapId: String, playlist: Playlist) async {
        guard let context = modelContext else { return }

        let targetMapId = mapId
        let descriptor = FetchDescriptor<PlaylistSongMap>(
            predicate: #Predicate<PlaylistSongMap> { map in
                map.id == targetMapId
            }
        )

        if let map = try? context.fetch(descriptor).first {
            context.delete(map)

            playlist.songCount -= 1
            playlist.dateModified = Date()

            try? context.save()
            await loadLocalData()
        }
    }

    func getPlaylistSongs(_ playlist: Playlist) async -> [Song] {
        guard let context = modelContext else { return [] }

        // For YouTube Music playlists, fetch from API if not in database
        if playlist.playlistType == .youtube {
            // Check if we have songs in database first
            let playlistId = playlist.id
            let descriptor = FetchDescriptor<PlaylistSongMap>(
                predicate: #Predicate<PlaylistSongMap> { map in
                    map.playlistId == playlistId
                },
                sortBy: [SortDescriptor(\.position)]
            )

            if let maps = try? context.fetch(descriptor), !maps.isEmpty {
                print("📋 [LibraryManager] Found \(maps.count) PlaylistSongMap entries for playlist \(playlist.id)")

                // Fix broken relationships if needed
                var needsFix = false
                for map in maps {
                    if map.song == nil {
                        needsFix = true
                        // Try to find the song by songId and fix the relationship
                        if let song = await getSong(id: map.songId) {
                            map.song = song
                        }
                    }
                }

                if needsFix {
                    print("📋 [LibraryManager] Fixed broken song relationships, saving...")
                    try? context.save()
                }

                let songs = maps.compactMap { $0.song }
                print("📋 [LibraryManager] Returning \(songs.count) songs from database")

                if songs.isEmpty {
                    print("📋 [LibraryManager] All songs are nil, fetching from API")
                } else {
                    // Check if database count matches expected count
                    // If not, the playlist has been updated (e.g., pagination was added), so re-fetch
                    if playlist.songCount > 0 && playlist.songCount != songs.count {
                        print("📋 [LibraryManager] Database has \(songs.count) songs but playlist expects \(playlist.songCount), re-fetching from API")
                        // Clear old mappings
                        for map in maps {
                            context.delete(map)
                        }
                        try? context.save()
                        // Fall through to fetch from API
                    } else {
                        return songs
                    }
                }
            }

            print("📋 [LibraryManager] No songs found in database, fetching from API")

            // Not in database, fetch from YouTube
            do {
                let rawId = playlist.browseId ?? playlist.id
                let browseId = (rawId.hasPrefix("VL") || rawId.hasPrefix("PL") || rawId.hasPrefix("FEmusic_") || rawId == "VLLM" || rawId.hasPrefix("MPSP")) ? rawId : "VL\(rawId)"
                let (ytPlaylist, ytSongs) = try await ytMusic.getPlaylist(browseId: browseId)

                // Update the playlist in database with correct song count
                playlist.songCount = ytSongs.count
                playlist.dateModified = Date()

                // Save songs to database
                var songs: [Song] = []
                print("📋 [LibraryManager] Saving \(ytSongs.count) songs to database")
                for (index, ytSong) in ytSongs.enumerated() {
                    await saveSong(ytSong)
                    if let song = await getSong(id: ytSong.id) {
                        songs.append(song)

                        // Add to playlist mapping
                        let map = PlaylistSongMap(
                            id: UUID().uuidString,
                            playlistId: playlist.id,
                            songId: song.id,
                            position: index
                        )

                        // CRITICAL: Set the relationship, not just the ID
                        map.song = song
                        map.playlist = playlist

                        context.insert(map)
                    }
                }

                print("📋 [LibraryManager] Created \(songs.count) PlaylistSongMap entries")
                try? context.save()
                print("📋 [LibraryManager] Database saved, playlist songCount updated to \(playlist.songCount)")

                // Reload library data to update UI with correct song counts
                await loadLocalData()

                return songs
            } catch {
                return []
            }
        }

        // For local playlists, get from database
        let playlistId = playlist.id
        let descriptor = FetchDescriptor<PlaylistSongMap>(
            predicate: #Predicate<PlaylistSongMap> { map in
                map.playlistId == playlistId
            },
            sortBy: [SortDescriptor(\.position)]
        )

        if let maps = try? context.fetch(descriptor) {
            return maps.compactMap { $0.song }
        }

        return []
    }

    // MARK: - Search History

    func addSearchHistory(query: String) {
        guard let context = modelContext else { return }

        let history = SearchHistory(
            id: UUID().uuidString,
            query: query
        )

        context.insert(history)
        try? context.save()
    }

    func getSearchHistory() -> [SearchHistory] {
        guard let context = modelContext else { return [] }

        var descriptor = FetchDescriptor<SearchHistory>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 20

        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Play Events (Matching Android)

    func trackPlayEvent(songId: String, playTime: Int64) {
        guard let context = modelContext else { return }

        let event = PlayEvent(
            songId: songId,
            timestamp: Date(),
            playTime: playTime
        )

        context.insert(event)
        try? context.save()

        // Refresh quick picks after tracking event
        Task {
            quickPicks = await getQuickPicks()
        }
    }

    private func getQuickPicks() async -> [Song] {
        guard let context = modelContext else { return [] }

        // Matching Android's query:
        // - Last 2 weeks (14 days)
        // - Group by albumId
        // - Sort by sum(playTime) DESC
        // - Shuffle and take 20

        let twoWeeksAgo = Date().addingTimeInterval(-14 * 24 * 60 * 60)

        // Get events from last 2 weeks
        let eventDescriptor = FetchDescriptor<PlayEvent>(
            predicate: #Predicate { $0.timestamp > twoWeeksAgo }
        )

        guard let events = try? context.fetch(eventDescriptor) else {
            return []
        }

        // Group by songId and calculate total play time
        var songPlayTimes: [String: Int64] = [:]
        for event in events {
            songPlayTimes[event.songId, default: 0] += event.playTime
        }

        // OPTIMIZATION: Fetch all songs in ONE query instead of N queries
        let songIds = Array(songPlayTimes.keys)

        // Early return if no songs to fetch
        guard !songIds.isEmpty else { return [] }

        let songDescriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { song in
                songIds.contains(song.id) && song.albumId != nil
            }
        )

        guard let songs = try? context.fetch(songDescriptor) else {
            return []
        }

        // Create lookup dictionary for O(1) access
        var songDict: [String: Song] = [:]
        for song in songs {
            songDict[song.id] = song
        }

        // Get songs with albums and their play times
        var songsWithAlbums: [(song: Song, playTime: Int64)] = []
        for (songId, playTime) in songPlayTimes {
            if let song = songDict[songId] {
                songsWithAlbums.append((song: song, playTime: playTime))
            }
        }

        // Group by albumId and get one song per album (the one with most play time)
        var albumSongs: [String: (song: Song, playTime: Int64)] = [:]
        for (song, playTime) in songsWithAlbums {
            guard let albumId = song.albumId else { continue }

            if let existing = albumSongs[albumId] {
                // Keep the song with more play time
                if playTime > existing.playTime {
                    albumSongs[albumId] = (song: song, playTime: playTime)
                }
            } else {
                albumSongs[albumId] = (song: song, playTime: playTime)
            }
        }

        // Sort by total play time DESC
        let sortedSongs = albumSongs.values
            .sorted { $0.playTime > $1.playTime }
            .map { $0.song }

        // Shuffle and take 20 (matching Android)
        return Array(sortedSongs.shuffled().prefix(20))
    }
}
