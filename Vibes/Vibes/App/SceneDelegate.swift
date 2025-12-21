import UIKit
import SwiftUI
import SwiftData

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Create SwiftData model container
        let modelContainer: ModelContainer
        do {
            modelContainer = try ModelContainer(for: Song.self, Album.self, Artist.self, Playlist.self, PlaylistSongMap.self, Format.self, SearchHistory.self, PlayEvent.self, Lyrics.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Set model context for managers
        let context = modelContainer.mainContext
        Task { @MainActor in
            LibraryManager.shared.setModelContext(context)
            LyricsManager.shared.setModelContext(context)
        }

        // Create the SwiftUI view
        let contentView = ContentView()
            .environmentObject(PlayerManager.shared)
            .environmentObject(AuthenticationManager.shared)
            .environmentObject(LibraryManager.shared)
            .environmentObject(QueueManager.shared)
            .environmentObject(LyricsManager.shared)
            .environmentObject(ThemeManager.shared)
            .modelContainer(modelContainer)

        // Create window and set root view controller
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called when the scene is being released by the system
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene moves from inactive to active state
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene moves from active to inactive state
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called when the scene moves from background to foreground
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called when the scene moves from foreground to background
    }
}
