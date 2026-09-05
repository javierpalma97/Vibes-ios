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
        guard self.modelContext !== context else { return }
        self.modelContext = context
        DebugLogger.shared.log("🔖 [LibraryManager] build cloudsync-2 (cookie-auth + counts + autosync)")

        // Load data asynchronously to avoid blocking UI on startup
        Task { @MainActor in
            await loadLocalData()
        }
    }

    private var autoSyncDone = false

    /// One automatic library sync per launch when authenticated. Fixes "nada se
    /// sincroniza hasta entrar en Biblioteca": previously sync only ran from
    /// LibraryView (pull-to-refresh / auth change).
    func autoSyncIfNeeded() {
        guard !autoSyncDone else { return }
        autoSyncDone = true
        guard InnerTubeClient.shared.isAuthenticated else { return }
        Task {
            do {
                try await syncLibrary()
            } catch {
                DebugLogger.shared.log("⚠️ [LibraryManager] auto-sync failed: \(error)")
            }
        }
    }

    func deleteAllData() {
        guard let context = modelContext else { return }
        let types: [any PersistentModel.Type] = [Song.self, Album.self, Artist.self, Playlist.self, PlaylistSongMap.self, Format.self, SearchHistory.self, PlayEvent.self, Lyrics.self]
        for t in types {
            do {
                try context.delete(model: t)
            } catch {
                dlog("⚠️ deleteAllData \(t) failed: \(error)")
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
            dlog("⚠️ clearSearchHistoryData failed: \(error)")
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
            dlog("📚 [LibraryManager] Loaded \(songs.count) liked songs")
        }

        // Load playlists
        let playlistDescriptor = FetchDescriptor<Playlist>(
            sortBy: [SortDescriptor(\.dateModified, order: .reverse)]
        )

        if let playlists = try? context.fetch(playlistDescriptor) {
            self.playlists = playlists
            dlog("📚 [LibraryManager] Loaded \(playlists.count) playlists")
        }

        // Load recently played
        var recentDescriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.playCount > 0 },
            sortBy: [SortDescriptor(\.dateModified, order: .reverse)]
        )
        recentDescriptor.fetchLimit = 50

        if let songs = try? context.fetch(recentDescriptor) {
            recentlyPlayed = songs
            dlog("📚 [LibraryManager] Loaded \(songs.count) recently played songs")
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
        dlog("📚 [LibraryManager] Loaded \(quickPicks.count) quick picks")
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
            dlog("⚠️ [LibraryManager] No model context for sync")
            await MainActor.run { DebugLogger.shared.log("⚠️ sync no ModelContext") }
            return
        }

        dlog("🔄 [LibraryManager] Starting library sync...")
        await MainActor.run { DebugLogger.shared.log("🔄 sync start isAuth=\(InnerTubeClient.shared.isAuthenticated) \(InnerTubeClient.shared.debugAuthState)") }
        // Vaciar primero la pool de tareas pendientes (likes/añadidos en espera)
        await pumpOutbox()
        if YouTubeDataAPI.isDisabled {
            DebugLogger.shared.log("⛔️ [LibraryManager] Data API off en este proyecto OAuth: cloud SOLO vía sesión web (Login → Conectar sesión web). Sin ella, todo queda local.")
        } else if OAuthManager.bearerHeaderSync != nil {
            DebugLogger.shared.log("☁️ [LibraryManager] Cloud ON (Data API): Me gusta y playlists se sincronizan.")
        } else if InnerTubeClient.shared.hasCookieAuth {
            DebugLogger.shared.log("☁️ [LibraryManager] Cloud parcial (sesión web): se intentará por InnerTube.")
        } else {
            DebugLogger.shared.log("☁️ [LibraryManager] Sin sesión: todo queda solo local. Inicia sesión para sincronizar en cloud.")
        }

        // Sync liked songs: Data API (oficial, completa) → fallback InnerTube VLLM
        do {
            await MainActor.run { DebugLogger.shared.log("📥 getLikedSongs start") }
            var ytLikedSongs: [YTSong] = []
            var likedVia = "innerTube"
            if OAuthManager.bearerHeaderSync != nil, !YouTubeDataAPI.isDisabled {
                do {
                    let items = try await YouTubeDataAPI.shared.getLikedItems()
                    ytLikedSongs = items.map {
                        YTSong(id: $0.videoId,
                               title: $0.title.isEmpty ? $0.videoId : $0.title,
                               artists: $0.artists,
                               duration: nil,
                               thumbnailUrl: $0.thumbnailUrl,
                               albumId: nil,
                               albumName: nil)
                    }
                    likedVia = "dataapi"
                } catch {
                    dlog("⚠️ [LibraryManager] DataAPI liked falló, usando VLLM: \(error)")
                    ytLikedSongs = try await ytMusic.getLikedSongs()
                }
            } else {
                ytLikedSongs = try await ytMusic.getLikedSongs()
            }
            dlog("📥 [LibraryManager] Syncing \(ytLikedSongs.count) liked songs (\(likedVia))...")
            await MainActor.run { DebugLogger.shared.log("✅ getLikedSongs \(ytLikedSongs.count) via=\(likedVia)") }
            for ytSong in ytLikedSongs {
                await saveSong(ytSong, liked: true, skipReload: true)
            }
            dlog("✅ [LibraryManager] Synced \(ytLikedSongs.count) liked songs")
        } catch {
            dlog("❌ [LibraryManager] Failed to sync liked songs: \(error)")
            await MainActor.run { DebugLogger.shared.log("❌ getLikedSongs \(error)") }
            throw error
        }

        // Sync playlists (batch mode to avoid reloading after each playlist)
        do {
            var ytPlaylists = try await ytMusic.getLibraryPlaylists()
            dlog("📥 [LibraryManager] Syncing \(ytPlaylists.count) playlists...")
            await MainActor.run { DebugLogger.shared.log("📥 getLibraryPlaylists \(ytPlaylists.count)") }
            // Fallback para cuentas con 1 sola lista creada por el usuario (a veces viene en carousel, no grid)
            if ytPlaylists.isEmpty {
                do {
                    let alt = try await ytMusic.getAccountPlaylists()
                    dlog("📚 [LibraryManager] Fallback getAccountPlaylists \(alt.count)")
                    await MainActor.run { DebugLogger.shared.log("📚 fallback accountPlaylists \(alt.count)") }
                    ytPlaylists = alt
                } catch {
                    dlog("⚠️ [LibraryManager] Fallback failed \(error)")
                }
            }
            for ytPlaylist in ytPlaylists {
                await savePlaylist(ytPlaylist, skipReload: true)
            }
            // Data API: listas propias con conteos REALES (itemCount). Gana a TV y
            // rellena lo que TV no trae. Merge (no sustituye: TV aporta guardadas).
            if OAuthManager.bearerHeaderSync != nil, !YouTubeDataAPI.isDisabled {
                do {
                    let cloud = try await YouTubeDataAPI.shared.getMyPlaylists()
                    for cp in cloud {
                        await savePlaylist(YTPlaylist(
                            id: cp.id,
                            name: cp.title,
                            author: cp.description,
                            thumbnailUrl: cp.thumbnailUrl,
                            songCount: cp.itemCount,
                            playlistId: nil
                        ), skipReload: true)
                    }
                    dlog("✅ [LibraryManager] DataAPI playlists: \(cloud.count) (conteos reales)")
                    await MainActor.run { DebugLogger.shared.log("📥 dataapi playlists \(cloud.count)") }
                } catch {
                    dlog("⚠️ [LibraryManager] DataAPI playlists falló: \(error)")
                }
            }
            dlog("✅ [LibraryManager] Synced \(ytPlaylists.count) playlists")
        } catch {
            dlog("❌ [LibraryManager] Failed to sync playlists: \(error)")
            await MainActor.run { DebugLogger.shared.log("❌ getLibraryPlaylists \(error)") }
            // Don't throw - partial sync is okay
        }

        // Sync albums
        do {
            let ytAlbums = try await ytMusic.getLibraryAlbums()
            dlog("📥 [LibraryManager] Syncing \(ytAlbums.count) albums...")
            await MainActor.run { DebugLogger.shared.log("📥 getLibraryAlbums \(ytAlbums.count)") }
            for ytAlbum in ytAlbums {
                await saveAlbum(ytAlbum, skipReload: true)
            }
            dlog("✅ [LibraryManager] Synced \(ytAlbums.count) albums")
        } catch {
            dlog("⚠️ [LibraryManager] Failed to sync albums: \(error)")
        }

        // Sync artists
        do {
            let ytArtists = try await ytMusic.getLibraryArtists()
            dlog("📥 [LibraryManager] Syncing \(ytArtists.count) artists...")
            await MainActor.run { DebugLogger.shared.log("📥 getLibraryArtists \(ytArtists.count)") }
            for ytArtist in ytArtists {
                await saveArtist(ytArtist, skipReload: true)
            }
            dlog("✅ [LibraryManager] Synced \(ytArtists.count) artists")
        } catch {
            dlog("⚠️ [LibraryManager] Failed to sync artists: \(error)")
        }

        // Refresh track counts for YouTube playlists (the list endpoint only gives
        // metadata, often with songCount 0; counts appear only after opening each
        // playlist otherwise). Single reload at the end.
        await refreshPlaylistCounts()

        // Drop legacy phantom rows ("Liked Music"/LM from older builds).
        await removeSystemPlaylistArtifacts()

        // Reload local data once at the end
        dlog("🔄 [LibraryManager] Reloading library data...")
        await loadLocalData()
        dlog("✅ [LibraryManager] Library sync complete")
    }

    /// Fetches the true track count of each YouTube playlist so the UI shows
    /// numbers without having to open every playlist. Songs themselves are
    /// still cached lazily on open (getPlaylistSongs).
    private func refreshPlaylistCounts() async {
        guard let context = modelContext else {
            DebugLogger.shared.log("🔢 [LibraryManager] refresh counts: no model context")
            return
        }
        // Read from the database, not from the published array (during sync with
        // skipReload the published array is still stale until the final reload).
        let descriptor = FetchDescriptor<Playlist>()
        guard let all = try? context.fetch(descriptor) else {
            DebugLogger.shared.log("🔢 [LibraryManager] refresh counts: DB fetch failed")
            return
        }
        let youtubePlaylists = all.filter { $0.playlistType == .youtube }
        DebugLogger.shared.log("🔢 [LibraryManager] refresh counts: total=\(all.count) youtube=\(youtubePlaylists.count)")
        guard !youtubePlaylists.isEmpty else { return }

        for pl in youtubePlaylists {
            do {
                let rawId = pl.browseId ?? pl.id
                let browseId = (rawId.hasPrefix("VL") || rawId.hasPrefix("PL") || rawId.hasPrefix("FEmusic_") || rawId == "VLLM" || rawId == "SE" || rawId.hasPrefix("RD") || rawId.hasPrefix("MPREb_") || rawId.hasPrefix("MPSP") || rawId.hasPrefix("UC")) ? rawId : "VL\(rawId)"
                let (ytPlaylist, _) = try await ytMusic.getPlaylist(browseId: browseId)
                if ytPlaylist.songCount > 0 && ytPlaylist.songCount != pl.songCount {
                    pl.songCount = ytPlaylist.songCount
                    pl.dateModified = Date()
                    try? context.save()
                    DebugLogger.shared.log("🔢 [LibraryManager] \(pl.name): songCount=\(pl.songCount)")
                } else {
                    DebugLogger.shared.log("🔢 [LibraryManager] \(pl.name): count unchanged (\(pl.songCount))")
                }
            } catch {
                DebugLogger.shared.log("⚠️ [LibraryManager] Count refresh failed for \(pl.name): \(error)")
            }
        }
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
            dlog("⚠️ [LibraryManager] No model context available")
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
            dlog("❌ [LibraryManager] Failed to save song \(ytSong.title): \(error)")
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
        await loadLocalData()

        // Cloud vía outbox (Data API oficial + reintentos). Se queda en local al
        // instante; la nube se actualiza en segundo plano y sobrevive a reinicios.
        if OAuthManager.bearerHeaderSync != nil {
            enqueueCloudTask(PendingCloudTask(
                id: UUID().uuidString, kind: .like, videoId: song.id,
                playlistId: nil, itemId: nil, liked: song.liked,
                attempts: 0, createdAt: Date()
            ))
        } else if InnerTubeClient.shared.hasCookieAuth {
            // Legacy: sesión web sin OAuth (WEB_REMIX+SAPISIDHASH)
            do {
                if song.liked {
                    try await ytMusic.likeSong(videoId: song.id)
                } else {
                    try await ytMusic.unlikeSong(videoId: song.id)
                }
                DebugLogger.shared.log("✅ [LibraryManager] toggleLike synced (web) \(song.title)")
            } catch {
                song.liked.toggle()
                if let context = modelContext {
                    try? context.save()
                }
                DebugLogger.shared.log("❌ [LibraryManager] toggleLike web failed, reverted: \(error)")
                await loadLocalData()
            }
        } else {
            DebugLogger.shared.log("⚠️ [LibraryManager] toggleLike solo local (sin sesión)")
        }
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
            dlog("❌ [LibraryManager] Failed to save playlist \(ytPlaylist.name): \(error)")
        }

        // Only reload if not in batch mode
        if !skipReload {
            await loadLocalData()
        }
    }

    /// Updates the cached song count of an EXISTING playlist. Unlike savePlaylist,
    /// it never inserts: opening a chart/trending playlist must not add it to
    /// "mis listas" (that was polluting the library with e.g. "Trending 20 Spain").
    func updatePlaylistCount(playlistId: String, songCount: Int) async {
        guard let context = modelContext else { return }

        let targetId = playlistId
        let descriptor = FetchDescriptor<Playlist>(
            predicate: #Predicate<Playlist> { p in
                p.id == targetId
            }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.songCount = songCount
            existing.dateModified = Date()
            try? context.save()
            await loadLocalData()
        }
    }

    /// Removes legacy "Liked Music" phantom rows (ids LM/VLLM) plus their orphan
    /// song maps. Older builds parsed the Liked system tile as a playlist, which
    /// broke add-to-playlist (edit_playlist on LM → 400). Real likes live in Song.liked.
    func removeSystemPlaylistArtifacts() async {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Playlist>()
        guard let all = try? context.fetch(descriptor) else { return }

        var removed = false
        for pl in all where pl.id == "LM" || pl.id == "VLLM" || pl.browseId == "VLLM" {
            let pid = pl.id
            let mapDescriptor = FetchDescriptor<PlaylistSongMap>(
                predicate: #Predicate<PlaylistSongMap> { m in
                    m.playlistId == pid
                }
            )
            if let maps = try? context.fetch(mapDescriptor) {
                for m in maps { context.delete(m) }
            }
            DebugLogger.shared.log("🧹 [LibraryManager] Removing phantom playlist \(pl.name) (\(pl.id))")
            context.delete(pl)
            removed = true
        }
        if removed {
            try? context.save()
            await loadLocalData()
        }
    }

    func createLocalPlaylist(name: String) async -> Playlist {
        guard let context = modelContext else {
            fatalError("ModelContext not set")
        }

        // Intentar crearla en cloud primero (Data API): así nace con identidad
        // única PL... y todo lo que se le añada sincroniza. Si falla, local.
        if OAuthManager.bearerHeaderSync != nil {
            do {
                let onlineId = try await YouTubeDataAPI.shared.createPlaylist(title: name)
                let playlist = Playlist(
                    id: onlineId,
                    name: name,
                    playlistType: .youtube,
                    songCount: 0,
                    browseId: onlineId
                )
                context.insert(playlist)
                try? context.save()
                await loadLocalData()
                DebugLogger.shared.log("✅ [LibraryManager] Playlist creada en cloud: \(name)")
                return playlist
            } catch {
                DebugLogger.shared.log("⚠️ [LibraryManager] Create online falló, será local: \(error)")
            }
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

        if playlist.playlistType == .youtube, playlist.id.hasPrefix("PL"),
           OAuthManager.bearerHeaderSync != nil {
            do {
                try await YouTubeDataAPI.shared.deletePlaylist(id: playlist.id)
                DebugLogger.shared.log("✅ [LibraryManager] Playlist borrada en cloud: \(playlist.name)")
            } catch {
                DebugLogger.shared.log("⚠️ [LibraryManager] Delete online falló (se borra en local): \(error)")
            }
        }

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

        // Cloud vía outbox (Data API). Solo listas de YouTube con id real (PL...).
        if playlist.playlistType == .youtube, playlist.id.hasPrefix("PL") {
            if OAuthManager.bearerHeaderSync != nil {
                enqueueCloudTask(PendingCloudTask(
                    id: UUID().uuidString, kind: .playlistAdd, videoId: song.id,
                    playlistId: playlist.id, itemId: nil, liked: nil,
                    attempts: 0, createdAt: Date()
                ))
            } else if InnerTubeClient.shared.hasCookieAuth {
                do {
                    try await ytMusic.addSongToPlaylist(playlistId: playlist.id, videoId: song.id)
                    dlog("✅ [LibraryManager] Synced song \(song.title) to online playlist \(playlist.name)")
                } catch {
                    dlog("⚠️ [LibraryManager] Failed online sync to playlist \(playlist.name): \(error)")
                }
            }
        }

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
            let removedSongId = map.songId
            context.delete(map)

            playlist.songCount -= 1
            playlist.dateModified = Date()

            try? context.save()

            if playlist.playlistType == .youtube, playlist.id.hasPrefix("PL"),
               OAuthManager.bearerHeaderSync != nil {
                enqueueCloudTask(PendingCloudTask(
                    id: UUID().uuidString, kind: .playlistRemove, videoId: removedSongId,
                    playlistId: playlist.id, itemId: nil, liked: nil,
                    attempts: 0, createdAt: Date()
                ))
            }

            await loadLocalData()
        }
    }

    // MARK: - Cloud Outbox (tareas pendientes con reintentos)

    private let outboxKey = "ytPendingCloudTasks"
    private let outboxMaxAttempts = 5
    private var outboxPumping = false

    private func loadOutbox() -> [PendingCloudTask] {
        guard let data = UserDefaults.standard.data(forKey: outboxKey),
              let tasks = try? JSONDecoder().decode([PendingCloudTask].self, from: data) else { return [] }
        return tasks
    }

    private func saveOutbox(_ tasks: [PendingCloudTask]) {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: outboxKey)
        }
    }

    /// Encola una mutación cloud (like / añadir / quitar) y fuerza su ejecución.
    /// La pool sobrevive a reinicios y se reintenta sola (al encolar, al sincronizar).
    func enqueueCloudTask(_ task: PendingCloudTask) {
        var tasks = loadOutbox()
        if task.kind == .like {
            // Coalescar: solo importa el último estado de cada vídeo
            tasks.removeAll { $0.kind == .like && $0.videoId == task.videoId }
        }
        tasks.append(task)
        saveOutbox(tasks)
        DebugLogger.shared.log("☁️ [Outbox] Encolada \(task.kind.rawValue) \(task.videoId) (pendientes: \(tasks.count))")
        Task { await pumpOutbox() }
    }

    /// Ejecuta la pool en orden FIFO.
    func pumpOutbox() async {
        guard !outboxPumping else { return }
        outboxPumping = true
        defer { outboxPumping = false }

        guard OAuthManager.bearerHeaderSync != nil else {
            if !loadOutbox().isEmpty {
                DebugLogger.shared.log("☁️ [Outbox] Sin OAuth: \(loadOutbox().count) tareas esperan sesión")
            }
            return
        }

        while true {
            var tasks = loadOutbox()
            guard !tasks.isEmpty else { return }
            let task = tasks.removeFirst()
            do {
                try await runCloudTask(task)
                saveOutbox(tasks)
                DebugLogger.shared.log("☁️ [Outbox] OK \(task.kind.rawValue) \(task.videoId)")
            } catch is OutboxNoRoute {
                // Sin ruta cloud posible: aparcar SIN gastar intentos (no es un fallo)
                tasks.append(task)
                saveOutbox(tasks)
                DebugLogger.shared.log("☁️ [Outbox] Sin ruta cloud: \(task.kind.rawValue) \(task.videoId) aparcada")
                return
            } catch {
                var failed = task
                failed.attempts += 1
                if failed.attempts >= outboxMaxAttempts {
                    saveOutbox(tasks)
                    DebugLogger.shared.log("❌ [Outbox] Descartada tras \(outboxMaxAttempts) intentos: \(task.kind.rawValue) \(task.videoId) (\(error))")
                    if task.kind == .like, let desired = task.liked {
                        await revertLike(videoId: task.videoId, desired: desired)
                    }
                } else {
                    tasks.append(failed)
                    saveOutbox(tasks)
                    DebugLogger.shared.log("⚠️ [Outbox] Fallo (\(failed.attempts)/\(outboxMaxAttempts)), reintento más tarde: \(error)")
                    return
                }
            }
        }
    }

    private func runCloudTask(_ task: PendingCloudTask) async throws {
        // Data API deshabilitada en este proyecto OAuth: única ruta, sesión web.
        if YouTubeDataAPI.isDisabled {
            guard InnerTubeClient.shared.hasCookieAuth else { throw OutboxNoRoute() }
            switch task.kind {
            case .like:
                if task.liked == true {
                    try await ytMusic.likeSong(videoId: task.videoId)
                } else {
                    try await ytMusic.unlikeSong(videoId: task.videoId)
                }
            case .playlistAdd:
                guard let playlistId = task.playlistId else { throw YouTubeDataError.badResponse("sin playlist") }
                try await ytMusic.addSongToPlaylist(playlistId: playlistId, videoId: task.videoId)
            case .playlistRemove:
                // InnerTube no puede quitar sin setVideoId: aparcada hasta Data API
                throw OutboxNoRoute()
            }
            return
        }
        switch task.kind {
        case .like:
            try await YouTubeDataAPI.shared.rateVideo(id: task.videoId, rating: task.liked == true ? .like : .none)
        case .playlistAdd:
            guard let playlistId = task.playlistId else { throw YouTubeDataError.badResponse("sin playlist") }
            _ = try await YouTubeDataAPI.shared.addVideoToPlaylist(playlistId: playlistId, videoId: task.videoId)
        case .playlistRemove:
            if let itemId = task.itemId {
                try await YouTubeDataAPI.shared.removeVideoFromPlaylist(itemId: itemId)
            } else if let playlistId = task.playlistId {
                let items = try await YouTubeDataAPI.shared.getPlaylistItems(playlistId: playlistId, max: 200)
                if let found = items.first(where: { $0.videoId == task.videoId }) {
                    try await YouTubeDataAPI.shared.removeVideoFromPlaylist(itemId: found.itemId)
                }
                // Si ya no está en cloud, se considera éxito
            } else {
                throw YouTubeDataError.badResponse("sin playlist")
            }
        }
    }

    private func revertLike(videoId: String, desired: Bool) async {
        guard let song = await getSong(id: videoId) else { return }
        song.liked = !desired
        song.dateModified = Date()
        if let context = modelContext {
            try? context.save()
        }
        await loadLocalData()
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
                dlog("📋 [LibraryManager] Found \(maps.count) PlaylistSongMap entries for playlist \(playlist.id)")

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
                    dlog("📋 [LibraryManager] Fixed broken song relationships, saving...")
                    try? context.save()
                }

                let songs = maps.compactMap { $0.song }
                dlog("📋 [LibraryManager] Returning \(songs.count) songs from database")

                if songs.isEmpty {
                    dlog("📋 [LibraryManager] All songs are nil, fetching from API")
                } else {
                    // Check if database count matches expected count
                    // If not, the playlist has been updated (e.g., pagination was added), so re-fetch
                    if playlist.songCount > 0 && playlist.songCount != songs.count {
                        dlog("📋 [LibraryManager] Database has \(songs.count) songs but playlist expects \(playlist.songCount), re-fetching from API")
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

            dlog("📋 [LibraryManager] No songs found in database, fetching from API")

            // Not in database, fetch from YouTube
            do {
                let rawId = playlist.browseId ?? playlist.id
                let browseId = (rawId.hasPrefix("VL") || rawId.hasPrefix("PL") || rawId.hasPrefix("FEmusic_") || rawId == "VLLM" || rawId == "SE" || rawId.hasPrefix("RD") || rawId.hasPrefix("MPREb_") || rawId.hasPrefix("MPSP") || rawId.hasPrefix("UC")) ? rawId : "VL\(rawId)"
                let (ytPlaylist, ytSongs) = try await ytMusic.getPlaylist(browseId: browseId)

                // Update the playlist in database with correct song count
                playlist.songCount = ytSongs.count
                playlist.dateModified = Date()

                // Save songs to database
                var songs: [Song] = []
                dlog("📋 [LibraryManager] Saving \(ytSongs.count) songs to database")
                for (index, ytSong) in ytSongs.enumerated() {
                    await saveSong(ytSong, skipReload: true)
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

                dlog("📋 [LibraryManager] Created \(songs.count) PlaylistSongMap entries")
                try? context.save()
                dlog("📋 [LibraryManager] Database saved, playlist songCount updated to \(playlist.songCount)")

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
