import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var playerManager: PlayerManager

    @AppStorage("audioQuality") private var audioQuality: String = "auto"
    @AppStorage("skipSilence") private var skipSilence: Bool = false
    @AppStorage("normalizeAudio") private var normalizeAudio: Bool = false
    @AppStorage("playbackSpeed") private var playbackSpeed: Double = 1.0

    var body: some View {
        NavigationStack {
            List {
                // Account Section
                Section(header: Text("Account")) {
                    if authManager.isAuthenticated {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.accentColor)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(authManager.accountName ?? "Signed In")
                                    .font(.headline)

                                if let email = authManager.accountEmail {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)

                        Button("Sign Out", role: .destructive) {
                            authManager.signOut()
                        }
                    } else {
                        NavigationLink(destination: LoginView()) {
                            Label("Sign in to YouTube Music", systemImage: "person.circle")
                        }
                    }
                }

                // Debug Section (sin necesidad de Mac/Console) - arriba para evitar barra mini-player
                Section(header: Text("Debug")) {
                    NavigationLink(destination: DebugLogView()) {
                        Label("Ver logs de reproducción", systemImage: "doc.text.magnifyingglass")
                    }
                }

                // OAuth2 Section (MusicBot #1670)
                Section(header: Text("YouTube OAuth2")) {
                    let oauth = OAuthManager.shared
                    if oauth.isAuthenticated {
                        Label("OAuth conectado", systemImage: "checkmark.seal.fill").foregroundColor(.green)
                        Button("Cerrar sesión OAuth", role: .destructive) { oauth.signOut() }
                    } else {
                        NavigationLink(destination: OAuthView()) {
                            Label("Iniciar OAuth2 (TV) – si cookies falla", systemImage: "tv")
                        }
                        Text("Usa cuenta burner. No requiere SAPISID.").font(.caption2).foregroundColor(.secondary)
                    }
                }

                // Playback Section
                Section(header: Text("Playback")) {
                    Picker("Audio Quality", selection: $audioQuality) {
                        Text("Auto").tag("auto")
                        Text("Low (48kbps)").tag("low")
                        Text("Medium (128kbps)").tag("medium")
                        Text("High (256kbps)").tag("high")
                    }

                    Picker("Playback Speed", selection: $playbackSpeed) {
                        Text("0.5x").tag(0.5)
                        Text("0.75x").tag(0.75)
                        Text("1.0x (Normal)").tag(1.0)
                        Text("1.25x").tag(1.25)
                        Text("1.5x").tag(1.5)
                        Text("2.0x").tag(2.0)
                    }
                    .onChange(of: playbackSpeed) { _, newValue in
                        playerManager.setPlaybackSpeed(newValue)
                    }

                    Toggle("Skip Silence", isOn: $skipSilence)
                    Toggle("Normalize Audio", isOn: $normalizeAudio)
                }

                // Cache Section
                Section(header: Text("Storage")) {
                    Button("Clear Cache") {
                        clearCache()
                    }

                    Button("Clear Search History") {
                        clearSearchHistory()
                    }

                    Button("Delete All Data", role: .destructive) {
                        deleteAllData()
                    }
                }

                // About Section
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/example/vibes-ios")!) {
                        Label("View Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }

                    NavigationLink(destination: AboutView()) {
                        Label("About Vibes", systemImage: "info.circle")
                    }
                }

                // Legal Section
                Section(header: Text("Legal")) {
                    NavigationLink(destination: DisclaimerView()) {
                        Label("Disclaimer", systemImage: "exclamationmark.triangle")
                    }

                    NavigationLink(destination: PrivacyView()) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }

            }
            .navigationTitle("Settings")
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
        }
    }

    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        let tmp = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for f in files where f.lastPathComponent.hasSuffix(".m4a") || f.lastPathComponent.hasSuffix(".wav") {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }

    private func clearSearchHistory() {
        LibraryManager.shared.clearSearchHistoryData()
    }

    private func deleteAllData() {
        LibraryManager.shared.deleteAllData()
        authManager.signOut()
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App Icon
                Image(systemName: "music.note")
                    .font(.system(size: 80))
                    .foregroundColor(.accentColor)
                    .padding(.top, 40)

                // App Name
                Text("Vibes iOS")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("A YouTube Music client for iOS")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Divider()
                    .padding(.vertical)

                // Credits
                VStack(alignment: .leading, spacing: 16) {
                    Text("Credits")
                        .font(.headline)

                    Text("Vibes iOS is a port of the original Vibes Android app. It uses the InnerTube API to stream music from YouTube Music.")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Text("This app is for personal use only and is not affiliated with Google or YouTube.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                Spacer()
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Disclaimer View

struct DisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Disclaimer")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top)

                Text("""
                This application uses reverse-engineered YouTube Music APIs and is provided for **personal use only**.

                **Important:**

                • This app is not affiliated with, endorsed by, or supported by Google/YouTube.

                • Using this app may violate YouTube's Terms of Service.

                • Do not distribute this app publicly or submit it to the App Store.

                • The developers are not responsible for any issues that may arise from using this app.

                • YouTube may break compatibility at any time without notice.

                By using this app, you acknowledge and accept these terms.
                """)
                .font(.body)

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Disclaimer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Privacy View

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top)

                Text("""
                **Data Collection:**

                This app does not collect, store, or transmit any personal data to external servers.

                **YouTube Account:**

                When you sign in with your YouTube account, authentication cookies are stored locally on your device to maintain your session. These cookies are never shared with third parties.

                **Local Storage:**

                Your library data, playlists, and preferences are stored locally on your device using SwiftData.

                **Network Requests:**

                All network requests are made directly to YouTube's servers. We do not intercept or log any of your activity.

                **Third-Party Services:**

                This app interacts with YouTube Music's servers. Please refer to Google's privacy policy for information about how they handle your data.
                """)
                .font(.body)

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
