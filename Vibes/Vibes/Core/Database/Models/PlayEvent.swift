import Foundation
import SwiftData

@Model
final class PlayEvent {
    @Attribute(.unique) var id: String
    var songId: String
    var timestamp: Date
    var playTime: Int64 // milliseconds

    init(id: String = UUID().uuidString, songId: String, timestamp: Date, playTime: Int64) {
        self.id = id
        self.songId = songId
        self.timestamp = timestamp
        self.playTime = playTime
    }
}
