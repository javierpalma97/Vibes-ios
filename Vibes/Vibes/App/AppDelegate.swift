import UIKit
import AVFoundation
import MediaPlayer

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure audio session for background playback
        setupAudioSession()

        // Setup remote command center
        setupRemoteCommandCenter()

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Handle CarPlay scene
        if connectingSceneSession.role == .carTemplateApplication {
            let config = UISceneConfiguration(name: "CarPlay Configuration", sessionRole: .carTemplateApplication)
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }

        // Handle default window scene
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        // Handle discarded scenes if needed
    }

    // MARK: - Audio Setup

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        let playerManager = PlayerManager.shared

        // Play/Pause
        commandCenter.playCommand.addTarget { _ in
            Task { @MainActor in
                playerManager.play()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { _ in
            Task { @MainActor in
                playerManager.pause()
            }
            return .success
        }

        // Next/Previous
        commandCenter.nextTrackCommand.addTarget { _ in
            Task { @MainActor in
                playerManager.playNext()
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { _ in
            Task { @MainActor in
                playerManager.playPrevious()
            }
            return .success
        }

        // Seek
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                Task { @MainActor in
                    playerManager.seek(to: event.positionTime)
                }
                return .success
            }
            return .commandFailed
        }
    }
}
