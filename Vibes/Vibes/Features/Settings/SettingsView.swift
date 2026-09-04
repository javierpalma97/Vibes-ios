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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Account
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Account")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(VibesColors.textPrimary)
                        if authManager.isAuthenticated {
                            HStack(spacing: 12) {
                                Image(systemName: "person.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(VibesColors.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(authManager.accountName ?? "Signed In")
                                        .font(.headline)
                                        .foregroundColor(VibesColors.textPrimary)
                                    if let email = authManager.accountEmail {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundColor(VibesColors.textSecondary)
                                    }
                                }
                                Spacer()
                            }
                            Button("Sign Out", role: .destructive) {
                                authManager.signOut()
                            }
                        } else {
                            NavigationLink(destination: LoginView()) {
                                HStack {
                                    Image(systemName: "person.circle")
                                        .foregroundColor(VibesColors.accent)
                                    Text("Sign in to YouTube Music")
                                        .foregroundColor(VibesColors.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(VibesColors.textTertiary)
                                }
                                .padding()
                                .background(VibesColors.card)
                                .cornerRadius(VibesRadius.row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)

                    // Playback
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Playback")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(VibesColors.textPrimary)
                        VStack(spacing: 0) {
                            HStack {
                                Text("Audio Quality")
                                    .foregroundColor(VibesColors.textPrimary)
                                Spacer()
                                Picker("Audio Quality", selection: $audioQuality) {
                                    Text("Auto").tag("auto")
                                    Text("Low").tag("low")
                                    Text("Medium").tag("medium")
                                    Text("High").tag("high")
                                }
                                .pickerStyle(.menu)
                                .tint(VibesColors.accent)
                            }
                            .padding(.vertical, 6)
                            Divider().background(VibesColors.elevated)
                            HStack {
                                Text("Playback Speed")
                                    .foregroundColor(VibesColors.textPrimary)
                                Spacer()
                                Picker("Playback Speed", selection: $playbackSpeed) {
                                    Text("0.5x").tag(0.5)
                                    Text("0.75x").tag(0.75)
                                    Text("1.0x").tag(1.0)
                                    Text("1.25x").tag(1.25)
                                    Text("1.5x").tag(1.5)
                                    Text("2.0x").tag(2.0)
                                }
                                .pickerStyle(.menu)
                                .tint(VibesColors.accent)
                            }
                            .padding(.vertical, 6)
                            .onChange(of: playbackSpeed) { _, newValue in
                                playerManager.setPlaybackSpeed(newValue)
                            }
                            Divider().background(VibesColors.elevated)
                            VibesToggleRow(title: "Skip Silence", isOn: $skipSilence)
                            Divider().background(VibesColors.elevated)
                            VibesToggleRow(title: "Normalize Audio", isOn: $normalizeAudio)
                        }
                        .padding(.horizontal, 12)
                        .background(VibesColors.card)
                        .cornerRadius(VibesRadius.row)
                    }
                    .padding(.horizontal)

                    // Storage
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Storage")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(VibesColors.textPrimary)
                        VStack(spacing: 0) {
                            SettingsActionRow(title: "Clear Cache", action: clearCache)
                            Divider().background(VibesColors.elevated)
                            SettingsActionRow(title: "Clear Search History", action: clearSearchHistory)
                            Divider().background(VibesColors.elevated)
                            SettingsActionRow(title: "Delete All Data", destructive: true, action: deleteAllData)
                        }
                        .padding(.horizontal, 12)
                        .background(VibesColors.card)
                        .cornerRadius(VibesRadius.row)
                    }
                    .padding(.horizontal)

                    // Debug
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Debug")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(VibesColors.textPrimary)
                        NavigationLink(destination: DebugLogView()) {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .foregroundColor(VibesColors.accent)
                                Text("Playback logs")
                                    .foregroundColor(VibesColors.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(VibesColors.textTertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(VibesColors.card)
                            .cornerRadius(VibesRadius.row)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)

                    // About
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(VibesColors.textPrimary)
                        VStack(spacing: 0) {
                            HStack {
                                Text("Version")
                                    .foregroundColor(VibesColors.textPrimary)
                                Spacer()
                                Text("1.0.0")
                                    .foregroundColor(VibesColors.textSecondary)
                            }
                            .padding(.vertical, 10)
                            Divider().background(VibesColors.elevated)
                            NavigationLink(destination: AboutView()) {
                                HStack {
                                    Text("About Vibes")
                                        .foregroundColor(VibesColors.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(VibesColors.textTertiary)
                                }
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            Divider().background(VibesColors.elevated)
                            NavigationLink(destination: DisclaimerView()) {
                                HStack {
                                    Text("Disclaimer")
                                        .foregroundColor(VibesColors.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(VibesColors.textTertiary)
                                }
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            Divider().background(VibesColors.elevated)
                            NavigationLink(destination: PrivacyView()) {
                                HStack {
                                    Text("Privacy Policy")
                                        .foregroundColor(VibesColors.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(VibesColors.textTertiary)
                                }
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .background(VibesColors.card)
                        .cornerRadius(VibesRadius.row)
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .vibesBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
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
        dlog("Cache cleared")
    }

    private func clearSearchHistory() {
        LibraryManager.shared.clearSearchHistoryData()
        dlog("Search history cleared")
    }

    private func deleteAllData() {
        LibraryManager.shared.deleteAllData()
        authManager.signOut()
    }
}

private struct SettingsActionRow: View {
    let title: String
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundColor(destructive ? .red : VibesColors.textPrimary)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "music.note")
                    .font(.system(size: 80))
                    .foregroundColor(VibesColors.accent)
                    .padding(.top, 40)

                Text("Vibes iOS")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(VibesColors.textPrimary)

                Text("A YouTube Music client for iOS")
                    .font(.subheadline)
                    .foregroundColor(VibesColors.textSecondary)

                Divider()
                    .padding(.vertical)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Credits")
                        .font(.headline)
                        .foregroundColor(VibesColors.textPrimary)

                    Text("Vibes iOS is a port of the original Vibes Android app. It uses the InnerTube API to stream music from YouTube Music.")
                        .font(.body)
                        .foregroundColor(VibesColors.textSecondary)

                    Text("This app is for personal use only and is not affiliated with Google or YouTube.")
                        .font(.caption)
                        .foregroundColor(VibesColors.textSecondary)
                }
                .padding(.horizontal)

                Spacer()
            }
        }
        .vibesBackground()
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
                    .foregroundColor(VibesColors.textPrimary)
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
                .foregroundColor(VibesColors.textSecondary)

                Spacer()
            }
            .padding()
        }
        .vibesBackground()
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
                    .foregroundColor(VibesColors.textPrimary)
                    .padding(.top)

                Text("""
                **Data Collection:**

                This app does not collect, store, or transmit any personal data to external servers.

                **YouTube Account:**

                When you sign in with your YouTube account, an OAuth token is stored securely on your device to maintain your session. It is never shared with third parties.

                **Local Storage:**

                Your library data, playlists, and preferences are stored locally on your device using SwiftData.

                **Network Requests:**

                All network requests are made directly to YouTube's servers. We do not intercept or log any of your activity.

                **Third-Party Services:**

                This app interacts with YouTube Music's servers. Please refer to Google's privacy policy for information about how they handle your data.
                """)
                .font(.body)
                .foregroundColor(VibesColors.textSecondary)

                Spacer()
            }
            .padding()
        }
        .vibesBackground()
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
