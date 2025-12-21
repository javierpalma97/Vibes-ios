import AppIntents
import SwiftUI

@available(iOS 16.0, *)
struct PlaySongIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Song"
    static var description = IntentDescription("Play a specific song in Vibes")

    @Parameter(title: "Song Name")
    var songName: String

    @Parameter(title: "Artist Name", default: "")
    var artistName: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let ytMusic = YouTubeMusic.shared
        let queueManager = QueueManager.shared

        // Search for the song
        let query = artistName.isEmpty ? songName : "\(artistName) \(songName)"

        do {
            let searchResults = try await ytMusic.search(query: query, filter: .songs)

            guard !searchResults.isEmpty else {
                throw NSError(domain: "Vibes", code: 404, userInfo: [NSLocalizedDescriptionKey: "Song not found"])
            }

            // Extract YTSong from SearchResult
            let songs = searchResults.compactMap { result -> YTSong? in
                if case .song(let song) = result {
                    return song
                }
                return nil
            }

            guard let firstSong = songs.first else {
                throw NSError(domain: "Vibes", code: 404, userInfo: [NSLocalizedDescriptionKey: "No songs found"])
            }

            // Convert to Song and play with radio mode enabled
            let song = Song(
                id: firstSong.id,
                title: firstSong.title,
                artistsText: firstSong.artists,
                durationText: firstSong.duration,
                thumbnailUrl: firstSong.thumbnailUrl,
                albumId: firstSong.albumId,
                albumName: firstSong.albumName
            )

            queueManager.setQueue([song], startIndex: 0, enableRadio: true)
            await queueManager.playAt(index: 0)

            return .result(dialog: "Now playing \(song.title)")

        } catch {
            throw NSError(domain: "Vibes", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to play song: \(error.localizedDescription)"])
        }
    }
}
