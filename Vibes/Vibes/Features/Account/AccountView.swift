import SwiftUI

struct AccountView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager

    @State private var ytPlaylists: [YTPlaylist] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let ytMusic = YouTubeMusic.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Account Header
                AccountHeader()

                // Quick Actions
                QuickActionsSection()

                // YouTube Playlists
                if authManager.isAuthenticated {
                    if isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    } else if let error = errorMessage {
                        VStack(spacing: 16) {
                            Text(error)
                                .foregroundColor(.secondary)

                            Button("Retry") {
                                Task {
                                    await loadPlaylists()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 40)
                    } else if !ytPlaylists.isEmpty {
                        YTPlaylistsSection(playlists: ytPlaylists)
                    }
                } else {
                    SignInPrompt()
                }

                Spacer(minLength: 120)
            }
            .padding(.top)
        }
        .navigationTitle("Account")
        .task {
            if authManager.isAuthenticated {
                await loadPlaylists()
            } else {
                isLoading = false
            }
        }
    }

    private func loadPlaylists() async {
        isLoading = true
        errorMessage = nil

        do {
            let playlists = try await ytMusic.getAccountPlaylists()
            await MainActor.run {
                ytPlaylists = playlists
            }
        } catch {
            print("❌ [Account] Error loading playlists: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load playlists"
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }
}

// MARK: - Account Header

struct AccountHeader: View {
    @EnvironmentObject var authManager: AuthenticationManager

    var body: some View {
        VStack(spacing: 16) {
            // Profile Picture
            if let imageUrl = authManager.accountImageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.gray)
            }

            // Name
            Text(authManager.accountName ?? "Guest")
                .font(.title2)
                .fontWeight(.bold)

            // Email
            if let email = authManager.accountEmail {
                Text(email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Sign Out Button
            if authManager.isAuthenticated {
                Button("Sign Out") {
                    authManager.signOut()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .padding()
    }
}

// MARK: - Quick Actions Section

struct QuickActionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    NavigationLink(destination: HistoryView()) {
                        QuickActionCard(
                            icon: "clock.arrow.circlepath",
                            title: "History",
                            color: .blue
                        )
                    }

                    NavigationLink(destination: StatsView()) {
                        QuickActionCard(
                            icon: "chart.bar.fill",
                            title: "Stats",
                            color: .pink
                        )
                    }

                    NavigationLink(destination: SettingsView()) {
                        QuickActionCard(
                            icon: "gearshape.fill",
                            title: "Settings",
                            color: .gray
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(color)
                .cornerRadius(12)

            Text(title)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .frame(width: 70)
    }
}

// MARK: - YouTube Playlists Section

struct YTPlaylistsSection: View {
    let playlists: [YTPlaylist]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your YouTube Playlists")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)

            ForEach(playlists.indices, id: \.self) { index in
                NavigationLink(destination: YTPlaylistDetailView(ytPlaylist: playlists[index])) {
                    YTPlaylistRow(playlist: playlists[index])
                }
            }
        }
    }
}

struct YTPlaylistRow: View {
    let playlist: YTPlaylist

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: playlist.thumbnailUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 56, height: 56)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let author = playlist.author {
                    Text(author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - Sign In Prompt

struct SignInPrompt: View {
    @State private var showLogin = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Sign in to YouTube Music")
                .font(.headline)

            Text("Access your playlists, liked songs, and listening history")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Sign In") {
                showLogin = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
    }
}
