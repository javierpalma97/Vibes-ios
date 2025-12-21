import AppIntents
import SwiftUI

@available(iOS 16.0, *)
struct PlayArtistIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Artist"
    static var description = IntentDescription("Play songs from a specific artist in Vibes")

    @Parameter(title: "Artist Name")
    var artistName: String

    @Parameter(title: "Shuffle", default: true)
    var shuffle: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        let ytMusic = YouTubeMusic.shared
        let queueManager = QueueManager.shared

        do {
            // Search for the artist
            let searchResults = try await ytMusic.search(query: artistName, filter: .artists)

            guard !searchResults.isEmpty else {
                throw NSError(domain: "Vibes", code: 404, userInfo: [NSLocalizedDescriptionKey: "Artist not found"])
            }

            // Extract YTArtist from SearchResult
            guard case .artist(let artist) = searchResults.first! else {
                throw NSError(domain: "Vibes", code: 404, userInfo: [NSLocalizedDescriptionKey: "Artist not found"])
            }

            // Get artist's songs
            let artistDetails = try await ytMusic.getArtist(browseId: artist.id)

            var songs: [Song] = []

            // Try to get songs from top songs section
            if let topSongsShelf = artistDetails.sections.first(where: { shelf in
                shelf.title.lowercased().contains("song")
            }) {
                songs = topSongsShelf.items.compactMap { item -> Song? in
                    if case .song(let ytSong) = item {
                        return Song(
                            id: ytSong.id,
                            title: ytSong.title,
                            artistsText: ytSong.artists,
                            durationText: ytSong.duration,
                            thumbnailUrl: ytSong.thumbnailUrl,
                            albumId: ytSong.albumId,
                            albumName: ytSong.albumName
                        )
                    }
                    return nil
                }
            }

            // Fallback: search for artist's songs
            if songs.isEmpty {
                let songResults = try await ytMusic.search(query: "\(artistName) songs", filter: .songs)

                let ytSongs = songResults.compactMap { result -> YTSong? in
                    if case .song(let song) = result {
                        return song
                    }
                    return nil
                }

                // Filter to only this artist's songs
                songs = ytSongs
                    .filter { $0.artists.lowercased().contains(artistName.lowercased()) }
                    .map { ytSong in
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
            }

            guard !songs.isEmpty else {
                throw NSError(domain: "Vibes", code: 404, userInfo: [NSLocalizedDescriptionKey: "No songs found for artist"])
            }

            // Limit to top 50 songs
            songs = Array(songs.prefix(50))

            // Set queue and play - DISABLE radio mode (only play this artist)
            queueManager.setQueue(songs, startIndex: 0, enableRadio: false)

            // Shuffle if requested
            if shuffle {
                queueManager.toggleShuffle()
            }

            await queueManager.playAt(index: 0)

            return .result(dialog: "Now playing \(artistName)")

        } catch {
            throw NSError(domain: "Vibes", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to play artist: \(error.localizedDescription)"])
        }
    }
}
