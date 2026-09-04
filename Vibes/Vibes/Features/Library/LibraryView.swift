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
                        Text("Playlists")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(VibesColors.textPrimary)
                        Spacer()
                        Button(action: { /* AirPlay / cast */ }) {
                            Image(systemName: "airplayvideo")
                                .font(.title2)
                                .foregroundColor(VibesColors.textPrimary)
                        }
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
            .alert("Sync Error", isPresented: $showSyncError) {
                if syncError?.contains("expired") == true {
                    Button("Sign In") {
                        showLogin = true
                    }
                    Button("Cancel", role: .cancel) { }
                } else {
                    Button("OK", role: .cancel) { }
                }
            } message: {
                Text(syncError ?? "An error occurred")
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
                    title: "Sign in to see playlists",
                    subtitle: "Sync your YouTube Music library",
                    actionTitle: "Sign In",
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
                        Text("Create New Playlist")
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
                        title: "Liked Songs",
                        subtitle: "\(libraryManager.likedSongs.count) songs",
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
                        title: "Top Songs",
                        subtitle: "Most played tracks",
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
                            subtitle: "\(playlist.songCount) songs",
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
                        Text(isSyncing ? "Syncing..." : "Sync Library")
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
                    syncError = "Sync authExpired – no se cierra sesión. Revisa DebugLog. \(InnerTubeClient.shared.debugAuthState)"
                    showSyncError = true
                }
                dlog("❌ [LibraryView] sync authExpired \(InnerTubeClient.shared.debugAuthState)")
            } catch InnerTubeError.notAuthenticated {
                await MainActor.run {
                    syncError = "Please sign in to sync your library."
                    showLogin = true
                }
            } catch InnerTubeError.invalidResponse {
                await MainActor.run {
                    syncError = "YouTube Music not set up. Please visit music.youtube.com in Safari, sign in, and like a song or create a playlist to initialize your library."
                    showSyncError = true
                }
            } catch {
                await MainActor.run {
                    syncError = "Sync failed: \(error.localizedDescription)"
                    showSyncError = true
                }
                dlog("Sync failed: \(error)")
            }
            isSyncing = false
        }
    }
}

// MARK: - Sort options

enum PlaylistSort: String, CaseIterable {
    case recentlyAdded = "Recently added"
    case name = "Name"
    case mostTracks = "Most tracks"
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
