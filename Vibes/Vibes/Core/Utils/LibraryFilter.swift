import Foundation

enum LibraryFilter: String, CaseIterable, Identifiable {
    case library = "All"
    case playlists = "Playlists"
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"

    var id: String { rawValue }
}
