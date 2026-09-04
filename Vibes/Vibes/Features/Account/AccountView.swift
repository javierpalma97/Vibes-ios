import SwiftUI

struct AccountView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager

    @State private var ytPlaylists: [YTPlaylist] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showSettings = false

    private let ytMusic = YouTubeMusic.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    AccountHeader()

                    QuickActionsSection()

                    if authManager.isAuthenticated {
                        if isLoading {
                            ProgressView()
                                .padding(.top, 40)
                        } else if let error = errorMessage {
                            VStack(spacing: 14) {
                                Text(error)
                                    .foregroundColor(VibesColors.textSecondary)

                                Button("Retry") {
                                    Task {
                                        await loadPlaylists()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(VibesColors.accent)
                                .foregroundColor(.black)
                            }
                            .padding(.top, 40)
                        } else if !ytPlaylists.isEmpty {
                            YTPlaylistsSection(playlists: ytPlaylists)
                        }
                    } else {
                        SignInPrompt()
                    }

                    Spacer(minLength: 140)
                }
                .padding(.top)
            }
            .vibesBackground()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(VibesColors.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task {
                if authManager.isAuthenticated {
                    await loadPlaylists()
                } else {
                    isLoading = false
                }
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
            dlog("❌ [Account] Error loading playlists: \(error)")
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
        VStack(spacing: 12) {
            if let imageUrl = authManager.accountImageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(VibesColors.elevated)
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(VibesColors.textTertiary)
            }

            Text(authManager.accountName ?? (authManager.isAuthenticated ? "Cuenta de YouTube Music" : "Invitado"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(VibesColors.textPrimary)

            if let email = authManager.accountEmail {
                Text(email)
                    .font(.subheadline)
                    .foregroundColor(VibesColors.textSecondary)
            }

            if authManager.isAuthenticated {
                Button("Cerrar sesión") {
                    authManager.signOut()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
    }
}

// MARK: - Quick Actions Section

struct QuickActionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Acciones rápidas")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(VibesColors.textPrimary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    NavigationLink(destination: HistoryView()) {
                        QuickActionCard(
                            icon: "clock.arrow.circlepath",
                            title: "Historial"
                        )
                    }

                    NavigationLink(destination: StatsView()) {
                        QuickActionCard(
                            icon: "chart.bar.fill",
                            title: "Estadísticas"
                        )
                    }

                    NavigationLink(destination: SettingsView()) {
                        QuickActionCard(
                            icon: "gearshape.fill",
                            title: "Ajustes"
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

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(VibesColors.accent)
                .frame(width: 50, height: 50)
                .background(VibesColors.accentDim)
                .cornerRadius(14)

            Text(title)
                .font(.caption)
                .foregroundColor(VibesColors.textPrimary)
        }
        .frame(width: 70)
    }
}

// MARK: - YouTube Playlists Section

struct YTPlaylistsSection: View {
    let playlists: [YTPlaylist]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tus Listas de YouTube")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(VibesColors.textPrimary)
                .padding(.horizontal)

            ForEach(playlists.indices, id: \.self) { index in
                NavigationLink(destination: YTPlaylistDetailView(ytPlaylist: playlists[index])) {
                    YTPlaylistRow(playlist: playlists[index])
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(VibesColors.card)
                        .cornerRadius(VibesRadius.row)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
        }
    }
}

struct YTPlaylistRow: View {
    let playlist: YTPlaylist

    var body: some View {
        VibesMediaRow(
            artworkUrl: playlist.thumbnailUrl,
            title: playlist.name,
            subtitle: playlist.author ?? "Lista"
        )
    }
}

// MARK: - Sign In Prompt

struct SignInPrompt: View {
    @State private var showLogin = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(VibesColors.textTertiary)

            Text("Inicia sesión en YouTube Music")
                .font(.headline)
                .foregroundColor(VibesColors.textPrimary)

            Text("Accede a tus listas, canciones favoritas e historial de reproducción")
                .font(.subheadline)
                .foregroundColor(VibesColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Iniciar Sesión") {
                showLogin = true
            }
            .buttonStyle(.borderedProminent)
            .tint(VibesColors.accent)
            .foregroundColor(.black)
        }
        .padding(.top, 40)
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
    }
}
