import SwiftUI
import SwiftData

@main
struct VibesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var playerManager = PlayerManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var libraryManager = LibraryManager.shared
    @StateObject private var queueManager = QueueManager.shared
    @StateObject private var lyricsManager = LyricsManager.shared
    @StateObject private var themeManager = ThemeManager.shared

    init() {
        // Global dark theme (mockup): transparent list backgrounds so every
        // legacy List screen inherits the dark background automatically.
        UITableView.appearance().backgroundColor = UIColor.clear
        UITableViewCell.appearance().backgroundColor = UIColor.clear
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(playerManager)
                .environmentObject(authManager)
                .environmentObject(libraryManager)
                .environmentObject(queueManager)
                .environmentObject(lyricsManager)
                .environmentObject(themeManager)
        }
        .modelContainer(for: [Song.self, Album.self, Artist.self, Playlist.self, PlaylistSongMap.self, Format.self, SearchHistory.self, PlayEvent.self, Lyrics.self])
    }
}
