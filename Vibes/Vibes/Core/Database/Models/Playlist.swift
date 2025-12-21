import Foundation
import SwiftData

enum PlaylistType: String, Codable {
    case local = "LOCAL"
    case youtube = "YOUTUBE"
}

@Model
final class Playlist {
    @Attribute(.unique) var id: String
    var name: String
    var thumbnailUrl: String?
    var playlistType: PlaylistType
    var dateAdded: Date
    var dateModified: Date
    var isEditable: Bool
    var songCount: Int

    // For YouTube playlists
    var browseId: String?
    var author: String?

    // Relationships
    @Relationship(deleteRule: .cascade) var items: [PlaylistSongMap]?

    init(
        id: String,
        name: String,
        thumbnailUrl: String? = nil,
        playlistType: PlaylistType = .local,
        dateAdded: Date = Date(),
        dateModified: Date = Date(),
        isEditable: Bool = true,
        songCount: Int = 0,
        browseId: String? = nil,
        author: String? = nil
    ) {
        self.id = id
        self.name = name
        self.thumbnailUrl = thumbnailUrl
        self.playlistType = playlistType
        self.dateAdded = dateAdded
        self.dateModified = dateModified
        self.isEditable = isEditable
        self.songCount = songCount
        self.browseId = browseId
        self.author = author
    }
}

@Model
final class PlaylistSongMap {
    @Attribute(.unique) var id: String
    var playlistId: String
    var songId: String
    var position: Int
    var dateAdded: Date

    // Relationships
    @Relationship(deleteRule: .nullify) var song: Song?
    @Relationship(deleteRule: .nullify, inverse: \Playlist.items) var playlist: Playlist?

    init(
        id: String,
        playlistId: String,
        songId: String,
        position: Int,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.playlistId = playlistId
        self.songId = songId
        self.position = position
        self.dateAdded = dateAdded
    }
}

@Model
final class SearchHistory {
    @Attribute(.unique) var id: String
    var query: String
    var timestamp: Date

    init(id: String, query: String, timestamp: Date = Date()) {
        self.id = id
        self.query = query
        self.timestamp = timestamp
    }
}
