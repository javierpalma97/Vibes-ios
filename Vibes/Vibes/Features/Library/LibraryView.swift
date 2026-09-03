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
    @State private var selectedFilter: LibraryFilter = .library

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(LibraryFilter.allCases) { filter in
                            Button(action: {
                                withAnimation {
                                    selectedFilter = filter
                                }
                            }) {
                                Text(filter.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedFilter == filter ? Color.accentColor : Color.gray.opacity(0.2))
                                    .foregroundColor(selectedFilter == filter ? .white : .primary)
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(UIColor.systemBackground))

                Divider()

                // Content based on selected filter
                if selectedFilter == .library {
                    libraryMixView
                } else if selectedFilter == .playlists {
                    playlistsView
                } else if selectedFilter == .songs {
                    LibrarySongsView()
                } else if selectedFilter == .albums {
                    LibraryAlbumsView()
                } else if selectedFilter == .artists {
                    LibraryArtistsView()
                }
            }
            .navigationTitle("Library")
            .refreshable {
                if authManager.isAuthenticated {
                    syncLibrary()
                    // Wait for sync to complete
                    while isSyncing {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: AccountView()) {
                        Image(systemName: "person.circle")
                    }
                }
            }
            .sheet(isPresented: $showLogin) {
                LoginView()
            }
            .sheet(isPresented: $showCreatePlaylist) {
                CreatePlaylistView()
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
        }
    }

    // MARK: - Library Mix View (default)

    private var libraryMixView: some View {
        List {
                // Account section
                Section {
                    if authManager.isAuthenticated {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(authManager.accountName ?? "Signed In")
                                    .font(.headline)

                                if let email = authManager.accountEmail {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button("Sign Out") {
                                authManager.signOut()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Button(action: {
                            syncLibrary()
                        }) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync Library")
                                if isSyncing {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isSyncing)
                    } else {
                        Button(action: {
                            showLogin = true
                        }) {
                            HStack {
                                Image(systemName: "person.circle")
                                Text("Sign in to YouTube Music")
                            }
                        }
                    }
                }

                // Downloads
                Section(header: Text("Downloads")) {
                    NavigationLink(destination: DownloadsView()) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.green)
                                .frame(width: 40, height: 40)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)

                            VStack(alignment: .leading) {
                                Text("Downloaded Songs")
                                    .font(.headline)
                                Text("Listen offline")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Auto Playlists
                Section(header: Text("Auto Playlists")) {
                    // Liked Songs
                    NavigationLink(destination: LikedSongsPlaylistView()) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .frame(width: 40, height: 40)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)

                            VStack(alignment: .leading) {
                                Text("Liked Songs")
                                    .font(.headline)
                                Text("\(libraryManager.likedSongs.count) songs")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Top Songs
                    NavigationLink(destination: TopSongsPlaylistView()) {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .foregroundColor(.blue)
                                .frame(width: 40, height: 40)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)

                            VStack(alignment: .leading) {
                                Text("Top Songs")
                                    .font(.headline)
                                Text("Most played tracks")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Playlists
                Section(header: HStack {
                    Text("Playlists")
                    Spacer()
                    Button(action: {
                        showCreatePlaylist = true
                    }) {
                        Image(systemName: "plus")
                    }
                }) {
                    ForEach(libraryManager.playlists) { playlist in
                        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: playlist.thumbnailUrl ?? "")) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay(
                                            Image(systemName: "music.note.list")
                                                .foregroundColor(.white)
                                        )
                                }
                                .frame(width: 56, height: 56)
                                .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name)
                                        .font(.body)
                                        .fontWeight(.medium)

                                    HStack {
                                        Text(playlist.playlistType == .local ? "Local" : "YouTube Music")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)

                                        Text("•")
                                            .foregroundColor(.secondary)

                                        Text("\(playlist.songCount) songs")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()
                            }
                        }
                    }
                }

                // Recently played
                if !libraryManager.recentlyPlayed.isEmpty {
                    Section(header: Text("Recently Played")) {
                        ForEach(libraryManager.recentlyPlayed.prefix(10)) { song in
                            Button(action: {
                                Task {
                                    await queueManager.setQueue([song])
                                }
                            }) {
                                SongRow(song: song)
                            }
                        }
                    }
                }
            }
        }

    // MARK: - Playlists View

    private var playlistsView: some View {
        List {
            // Playlists
            Section(header: HStack {
                Text("Playlists")
                Spacer()
                Button(action: {
                    showCreatePlaylist = true
                }) {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(libraryManager.playlists) { playlist in
                    NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: playlist.thumbnailUrl ?? "")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay(
                                        Image(systemName: "music.note.list")
                                            .foregroundColor(.white)
                                    )
                            }
                            .frame(width: 56, height: 56)
                            .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlist.name)
                                    .font(.body)
                                    .fontWeight(.medium)

                                HStack {
                                    Text(playlist.playlistType == .local ? "Local" : "YouTube Music")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    Text("•")
                                        .foregroundColor(.secondary)

                                    Text("\(playlist.songCount) songs")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()
                        }
                    }
                }
            }
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
                    // No hacer signOut automático – deja que el usuario decida, solo muestra error con detalle
                    DebugLogger.shared.log("❌ sync authExpired \(InnerTubeClient.shared.debugAuthState)")
                    syncError = "Sync authExpired – no se cierra sesión. Revisa DebugLog. \(InnerTubeClient.shared.debugAuthState)"
                    showSyncError = true
                }
                print("❌ [LibraryView] sync authExpired \(InnerTubeClient.shared.debugAuthState)")
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
                print("Sync failed: \(error)")
            }
            isSyncing = false
        }
    }
}

struct SongRow: View {
    let song: Song
    @StateObject private var downloadManager = DownloadManager.shared

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: song.thumbnailUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 48, height: 48)
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(song.artistsText ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Download status indicator
            DownloadStatusIndicator(songId: song.id)
        }
    }
}

struct CreatePlaylistView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var libraryManager: LibraryManager

    @State private var playlistName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Playlist Name", text: $playlistName)
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            _ = await libraryManager.createLocalPlaylist(name: playlistName)
                            dismiss()
                        }
                    }
                    .disabled(playlistName.isEmpty)
                }
            }
        }
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager

    let playlist: Playlist

    @State private var songs: [Song] = []

    var body: some View {
        List {
            // Playlist header with actions
            Section {
                HStack(spacing: 16) {
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
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
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
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                    .disabled(songs.isEmpty)
                }
                .buttonStyle(PlainButtonStyle())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                // Download All button
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
                    .foregroundColor(.accentColor)
                }
                .disabled(songs.isEmpty)
            }

            // Songs list
            Section(header: Text("\(songs.count) songs")) {
                ForEach(songs) { song in
                    Button(action: {
                        Task {
                            await queueManager.setQueue(songs, startIndex: songs.firstIndex(where: { $0.id == song.id }) ?? 0)
                        }
                    }) {
                        SongRow(song: song)
                    }
                    .songContextMenu(song: song)
                }
            }
        }
        .navigationTitle(playlist.name)
        .task {
            songs = await libraryManager.getPlaylistSongs(playlist)
        }
    }
}
