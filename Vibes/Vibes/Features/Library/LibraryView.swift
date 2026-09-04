import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager

    @State private var showLogin: Bool = false
    @State private var showCreatePlaylist: Bool = false
    @State private var isSyncing: Bool = false
    @State private var syncError: String?
    @State private var showSyncError: Bool = false
    @State private var selectedTab: VibesLibraryTab = .playlists
    @State private var sortOption: PlaylistSort = .recentlyAdded
    @State private var showSettings: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        Text("Listas de reproducción")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(VibesColors.textPrimary)
                        Spacer()
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.title2)
                                .foregroundColor(VibesColors.textPrimary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Tabs
                    VibesLibraryTabs(selection: $selectedTab)
                        .padding(.horizontal)

                    // Content per tab
                    switch selectedTab {
                    case .playlists:
                        playlistsContent
                    case .albums:
                        LibraryAlbumsView()
                    case .artists:
                        LibraryArtistsView()
                    case .downloads:
                        DownloadsView()
                    }

                    Spacer(minLength: 140)
                }
            }
            .vibesBackground()
            .refreshable {
                if authManager.isAuthenticated {
                    syncLibrary()
                    while isSyncing {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
            }
            .sheet(isPresented: $showLogin) {
                LoginView()
            }
            .sheet(isPresented: $showCreatePlaylist) {
                CreatePlaylistView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("Error de Sincronización", isPresented: $showSyncError) {
                if syncError?.contains("expired") == true {
                    Button("Iniciar Sesión") {
                        showLogin = true
                    }
                    Button("Cancelar", role: .cancel) { }
                } else {
                    Button("Aceptar", role: .cancel) { }
                }
            } message: {
                Text(syncError ?? "Ha ocurrido un error")
            }
            .onChange(of: authManager.isAuthenticated) { _, newValue in
                if newValue && !isSyncing {
                    syncLibrary()
                }
            }
        }
    }

    // MARK: - Playlists tab

    private var playlistsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Sort row
            HStack {
                Menu {
                    ForEach(PlaylistSort.allCases, id: \.self) { option in
                        Button(action: { sortOption = option }) {
                            Label(option.rawValue, systemImage: sortOption == option ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(sortOption.rawValue)
                            .font(.subheadline)
                            .foregroundColor(VibesColors.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(VibesColors.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundColor(VibesColors.textSecondary)
            }
            .padding(.horizontal)

            if !authManager.isAuthenticated {
                VibesEmptyState(
                    icon: "person.circle",
                    title: "Inicia sesión para ver tus listas",
                    subtitle: "Sincroniza tu biblioteca de YouTube Music",
                    actionTitle: "Iniciar Sesión",
                    action: { showLogin = true }
                )
                .padding(.horizontal)
            } else {
                // Create button
                Button(action: { showCreatePlaylist = true }) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(VibesColors.elevated)
                                .frame(width: 56, height: 56)
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(VibesColors.textPrimary)
                        }
                        Text("Crear nueva lista")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(VibesColors.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(VibesColors.card)
                    .cornerRadius(VibesRadius.row)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                // Auto playlists
                NavigationLink(destination: LikedSongsPlaylistView()) {
                    VibesMediaRow(
                        artworkUrl: nil,
                        title: "Me gusta",
                        subtitle: "\(libraryManager.likedSongs.count) canciones",
                        fallbackIcon: "heart.fill"
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(VibesColors.card)
                    .cornerRadius(VibesRadius.row)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                NavigationLink(destination: TopSongsPlaylistView()) {
                    VibesMediaRow(
                        artworkUrl: nil,
                        title: "Más escuchadas",
                        subtitle: "Canciones más reproducidas",
                        fallbackIcon: "chart.bar.fill"
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(VibesColors.card)
                    .cornerRadius(VibesRadius.row)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                // User playlists
                ForEach(sortedPlaylists) { playlist in
                    NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                        VibesMediaRow(
                            artworkUrl: playlist.thumbnailUrl,
                            title: playlist.name,
                            subtitle: "\(playlist.songCount) canciones",
                            onMenu: {}
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(VibesColors.card)
                        .cornerRadius(VibesRadius.row)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                // Sync button
                Button(action: { syncLibrary() }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(isSyncing ? "Sincronizando..." : "Sincronizar biblioteca")
                        if isSyncing {
                            Spacer()
                            ProgressView()
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(VibesColors.accent)
                }
                .disabled(isSyncing)
                .padding(.horizontal)
                .padding(.top, 4)
            }
        }
    }

    private var sortedPlaylists: [Playlist] {
        switch sortOption {
        case .recentlyAdded:
            return libraryManager.playlists
        case .name:
            return libraryManager.playlists.sorted { $0.name < $1.name }
        case .mostTracks:
            return libraryManager.playlists.sorted { $0.songCount > $1.songCount }
        }
    }

    // MARK: - Sync

    private func syncLibrary() {
        isSyncing = true
        Task {
            do {
                try await libraryManager.syncLibrary()
            } catch InnerTubeError.authenticationExpired {
                await MainActor.run {
                    DebugLogger.shared.log("❌ sync authExpired \(InnerTubeClient.shared.debugAuthState)")
                    syncError = "Sesión expirada. Revisa DebugLog. \(InnerTubeClient.shared.debugAuthState)"
                    showSyncError = true
                }
            } catch InnerTubeError.notAuthenticated {
                await MainActor.run {
                    syncError = "Por favor inicia sesión para sincronizar."
                    showLogin = true
                }
            } catch InnerTubeError.invalidResponse {
                await MainActor.run {
                    syncError = "YouTube Music no inicializado. Entra en music.youtube.com y da me gusta a una canción."
                    showSyncError = true
                }
            } catch {
                await MainActor.run {
                    syncError = "Error al sincronizar: \(error.localizedDescription)"
                    showSyncError = true
                }
            }
            isSyncing = false
        }
    }
}

// MARK: - Sort options

enum PlaylistSort: String, CaseIterable {
    case recentlyAdded = "Añadidas recientemente"
    case name = "Nombre"
    case mostTracks = "Más canciones"
}

// MARK: - Song row (shared, pure row: callers wrap tap behavior)

struct SongRow: View {
    let song: Song

    var body: some View {
        VibesTrackRow(song: song)
            .songContextMenu(song: song)
    }
}

// MARK: - Create playlist

struct CreatePlaylistView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var libraryManager: LibraryManager

    @State private var playlistName: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VibesSearchBar(text: $playlistName, placeholder: "Playlist name")
                    .padding(.horizontal)
                    .padding(.top, 20)
                Spacer()
            }
            .vibesBackground()
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(VibesColors.textPrimary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            _ = await libraryManager.createLocalPlaylist(name: playlistName)
                            dismiss()
                        }
                    }
                    .disabled(playlistName.isEmpty)
                    .foregroundColor(VibesColors.accent)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Local playlist detail

struct PlaylistDetailView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager

    let playlist: Playlist

    @State private var songs: [Song] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await queueManager.setQueue(songs)
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(VibesColors.accent)
                        .foregroundColor(.black)
                        .fontWeight(.semibold)
                        .cornerRadius(12)
                    }
                    .disabled(songs.isEmpty)

                    Button(action: {
                        Task {
                            await queueManager.setQueue(songs.shuffled())
                        }
                    }) {
                        HStack {
                            Image(systemName: "shuffle")
                            Text("Shuffle")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(VibesColors.elevated)
                        .foregroundColor(VibesColors.textPrimary)
                        .cornerRadius(12)
                    }
                    .disabled(songs.isEmpty)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                Button(action: {
                    Task {
                        await DownloadManager.shared.downloadMultiple(songs: songs)
                    }
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                        Text("Download All")
                        Spacer()
                    }
                    .foregroundColor(VibesColors.accent)
                }
                .disabled(songs.isEmpty)
                .padding(.horizontal)

                Text("\(songs.count) songs")
                    .font(.subheadline)
                    .foregroundColor(VibesColors.textSecondary)
                    .padding(.horizontal)

                LazyVStack(spacing: 4) {
                    ForEach(songs) { song in
                        Button(action: {
                            Task {
                                await queueManager.setQueue(songs, startIndex: songs.firstIndex(where: { $0.id == song.id }) ?? 0)
                            }
                        }) {
                            SongRow(song: song)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(VibesColors.card)
                                .cornerRadius(VibesRadius.row)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }

                Spacer(minLength: 140)
            }
            .padding(.top)
        }
        .vibesBackground()
        .navigationTitle(playlist.name)
        .task {
            songs = await libraryManager.getPlaylistSongs(playlist)
        }
    }
}
