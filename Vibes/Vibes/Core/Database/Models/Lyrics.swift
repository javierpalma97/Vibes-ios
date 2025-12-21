import Foundation
import SwiftData

@Model
final class Lyrics {
    @Attribute(.unique) var songId: String
    var lines: [LyricsLine]
    var synced: Bool  // True if timestamped, false if plain text
    var source: String  // Provider name (lrclib, kugou, youtube, etc.)
    var dateAdded: Date

    init(songId: String, lines: [LyricsLine], synced: Bool, source: String, dateAdded: Date = Date()) {
        self.songId = songId
        self.lines = lines
        self.synced = synced
        self.source = source
        self.dateAdded = dateAdded
    }
}

struct LyricsLine: Codable, Hashable {
    var timestamp: TimeInterval?  // Seconds from start (nil for unsynced lyrics)
    var text: String

    init(timestamp: TimeInterval? = nil, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
}
