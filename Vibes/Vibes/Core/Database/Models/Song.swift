import Foundation
import SwiftData

@Model
final class Song {
    @Attribute(.unique) var id: String
    var title: String
    var artistsText: String?
    var durationText: String?
    var thumbnailUrl: String?
    var albumId: String?
    var albumName: String?
    var liked: Bool
    var totalPlayTime: Int
    var playCount: Int
    var dateAdded: Date
    var dateModified: Date

    // Relationships
    @Relationship(deleteRule: .nullify) var artists: [Artist]?
    @Relationship(deleteRule: .nullify) var album: Album?
    @Relationship(deleteRule: .cascade) var format: Format?

    init(
        id: String,
        title: String,
        artistsText: String? = nil,
        durationText: String? = nil,
        thumbnailUrl: String? = nil,
        albumId: String? = nil,
        albumName: String? = nil,
        liked: Bool = false,
        totalPlayTime: Int = 0,
        playCount: Int = 0,
        dateAdded: Date = Date(),
        dateModified: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.artistsText = artistsText
        self.durationText = durationText
        self.thumbnailUrl = thumbnailUrl
        self.albumId = albumId
        self.albumName = albumName
        self.liked = liked
        self.totalPlayTime = totalPlayTime
        self.playCount = playCount
        self.dateAdded = dateAdded
        self.dateModified = dateModified
    }

    // Helper computed properties
    var duration: TimeInterval? {
        guard let durationText = durationText else { return nil }
        return parseDuration(durationText)
    }

    private func parseDuration(_ text: String) -> TimeInterval? {
        let components = text.split(separator: ":").compactMap { Int($0) }
        switch components.count {
        case 2: // MM:SS
            return TimeInterval(components[0] * 60 + components[1])
        case 3: // HH:MM:SS
            return TimeInterval(components[0] * 3600 + components[1] * 60 + components[2])
        default:
            return nil
        }
    }
}

@Model
final class Format {
    @Attribute(.unique) var id: String
    var songId: String
    var itag: Int
    var mimeType: String
    var codec: String
    var bitrate: Int
    var sampleRate: Int
    var contentLength: Int
    var loudnessDb: Double?
    var url: String?
    var urlExpiry: Date?

    init(
        id: String,
        songId: String,
        itag: Int,
        mimeType: String,
        codec: String,
        bitrate: Int,
        sampleRate: Int,
        contentLength: Int,
        loudnessDb: Double? = nil,
        url: String? = nil,
        urlExpiry: Date? = nil
    ) {
        self.id = id
        self.songId = songId
        self.itag = itag
        self.mimeType = mimeType
        self.codec = codec
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.contentLength = contentLength
        self.loudnessDb = loudnessDb
        self.url = url
        self.urlExpiry = urlExpiry
    }

    var isExpired: Bool {
        guard let expiry = urlExpiry else { return true }
        return Date() >= expiry
    }
}
