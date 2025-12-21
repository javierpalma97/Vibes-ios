import AppIntents
import SwiftUI
import SwiftData

@available(iOS 16.0, *)
struct PlayPlaylistIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Playlist"
    static var description = IntentDescription("Play a specific playlist in Vibes")

    @Parameter(title: "Playlist Name")
    var playlistName: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let ytMusic = YouTubeMusic.shared
        let queueManager = QueueManager.shared
        let libraryManager = LibraryManager.shared

        // Check for special local playlists first
        let lowercaseName = playlistName.lowercased()

        if lowercaseName.contains("liked") || lowercaseName.contains("favorite") {
            // Play liked songs
            let likedSongs = libraryManager.likedSongs
            guard !likedSongs.isEmpty else {
                throw NSError(domain: "Vibes", code: 404, userInfo: [NSLocalizedDescriptionKey: "No liked songs found"])
            }

            queueManager.setQueue(likedSongs, startIndex: 0, enableRadio: true)
            await queueManager.playAt(index: 0)
            return .result(dialog: "Now playing Liked Songs")
        }

        if lowercaseName.contains("download") {
            // Play downloaded songs
            let downloadManager = DownloadManager.shared
            let downloadedIds = downloadManager.getDownloadedSongIds()

            guard !downloadedIds.isEmpty else {
                throw NSError(domain: "Vibes", code: 404, userInfo: [NSLocalizedDescriptionKey: "No downloaded songs found"])
            }

            // Filter liked songs to only downloaded ones
            let downloadedSongs = libraryManager.likedSongs.filter { downloadedIds.contains($0.id) }

            // If no liked songs are downloaded, just play all downloaded songs from liked
            if downloadedSongs.isEmpty {
                // Play the first 50 downloaded song IDs (limited for performance)
                let limitedIds = Array(downloadedIds.prefix(50))
                // We'll need to search for these songs - for now just return error
                throw NSError(domain: "Vibes", code: 404, userInfo: [NSLocalizedDescriptionKey: "Downloaded songs not in library. Add downloaded songs to liked songs first."])
            }

            queueManager.setQueue(downloadedSongs, startIndex: 0, enableRadio: true)
            await queueManager.playAt(index: 0)
            return .result(dialog: "Now playing Downloaded Songs")
        }

        if lowercaseName.contains("top") || lowercaseName.contains("most played") {
            // Play top songs - use liked songs sorted by play count
            let topSongs = libraryManager.likedSongs
                .sorted { $0.playCount > $1.playCount }
                .prefix(100)

            guard !topSongs.isEmpty else {
                throw NSError(domain: "Vibes", code: 404, userInfo: [NSLocalizedDescriptionKey: "No liked songs found for top songs"])
            }

            queueManager.setQueue(Array(topSongs), startIndex: 0, enableRadio: true)
            await queueManager.playAt(index: 0)
            return .result(dialog: "Now playing Top Songs")
        }

        // Search for YouTube Music playlist
        do {
            let searchResults = try await ytMusic.search(query: playlistName, filter: .playlists)

            guard !searchResults.isEmpty else {
                throw NSError(domain: "Vibes", code: 404, userInfo: [NSLocalizedDescriptionKey: "Playlist not found"])
            }

            // Extract YTPlaylist from SearchResult
            guard case .playlist(let playlist) = searchResults.first! else {
                throw NSError(domain: "Vibes", code: 404, userInfo: [NSLocalizedDescriptionKey: "Playlist not found"])
            }

            let (_, ytSongs) = try await ytMusic.getPlaylist(browseId: playlist.id)

            guard !ytSongs.isEmpty else {
                throw NSError(domain: "Vibes", code: 404, userInfo: [NSLocalizedDescriptionKey: "Playlist is empty"])
            }

            let songs = ytSongs.map { ytSong in
                Song(
                    id: ytSong.id,
                    title: ytSong.title,
                    artistsText: ytSong.artists,
                    durationText: ytSong.duration,
                    thumbnailUrl: ytSong.thumbnailUrl,
                    albumId: ytSong.albumId,
                    albumName: ytSong.albumName
                )
            }

            // Enable radio mode for playlists - will activate AFTER playlist ends
            queueManager.setQueue(songs, startIndex: 0, enableRadio: true)
            await queueManager.playAt(index: 0)

            return .result(dialog: "Now playing \(playlist.name)")

        } catch {
            throw NSError(domain: "Vibes", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to play playlist: \(error.localizedDescription)"])
        }
    }
}
