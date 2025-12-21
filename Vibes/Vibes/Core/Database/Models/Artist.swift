import Foundation
import SwiftData

@Model
final class Artist {
    @Attribute(.unique) var id: String
    var name: String
    var thumbnailUrl: String?
    var isSubscribed: Bool
    var totalPlayTime: Int
    var playCount: Int
    var dateAdded: Date

    // Relationships
    @Relationship(inverse: \Song.artists) var songs: [Song]?
    @Relationship(inverse: \Album.artists) var albums: [Album]?

    init(
        id: String,
        name: String,
        thumbnailUrl: String? = nil,
        isSubscribed: Bool = false,
        totalPlayTime: Int = 0,
        playCount: Int = 0,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.thumbnailUrl = thumbnailUrl
        self.isSubscribed = isSubscribed
        self.totalPlayTime = totalPlayTime
        self.playCount = playCount
        self.dateAdded = dateAdded
    }
}

@Model
final class Album {
    @Attribute(.unique) var id: String
    var title: String
    var artistsText: String?
    var year: String?
    var thumbnailUrl: String?
    var isExplicit: Bool
    var liked: Bool
    var totalPlayTime: Int
    var playCount: Int
    var dateAdded: Date

    // Relationships
    @Relationship(deleteRule: .nullify) var artists: [Artist]?
    @Relationship(inverse: \Song.album) var songs: [Song]?

    init(
        id: String,
        title: String,
        artistsText: String? = nil,
        year: String? = nil,
        thumbnailUrl: String? = nil,
        isExplicit: Bool = false,
        liked: Bool = false,
        totalPlayTime: Int = 0,
        playCount: Int = 0,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.artistsText = artistsText
        self.year = year
        self.thumbnailUrl = thumbnailUrl
        self.isExplicit = isExplicit
        self.liked = liked
        self.totalPlayTime = totalPlayTime
        self.playCount = playCount
        self.dateAdded = dateAdded
    }

    var artistName: String? {
        return artistsText
    }

    func toYTAlbum() -> YTAlbum {
        return YTAlbum(
            id: id,
            title: title,
            artists: artistsText ?? "",
            year: year,
            thumbnailUrl: thumbnailUrl
        )
    }
}

extension Artist {
    func toYTArtist() -> YTArtist {
        return YTArtist(
            id: id,
            name: name,
            thumbnailUrl: thumbnailUrl
        )
    }
}
