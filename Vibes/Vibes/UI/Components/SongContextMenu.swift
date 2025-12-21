import SwiftUI

struct SongContextMenu: View {
    let song: Song
    let onAddToQueue: () -> Void
    let onPlayNext: () -> Void
    let onAddToPlaylist: () -> Void
    let onToggleLike: () -> Void
    let onGoToArtist: () -> Void
    let onGoToAlbum: () -> Void
    let onShare: () -> Void

    @EnvironmentObject var libraryManager: LibraryManager

    var body: some View {
        Group {
            Button(action: onPlayNext) {
                Label("Play Next", systemImage: "text.insert")
            }

            Button(action: onAddToQueue) {
                Label("Add to Queue", systemImage: "text.append")
            }

            Divider()

            Button(action: onAddToPlaylist) {
                Label("Add to Playlist", systemImage: "plus.rectangle.on.folder")
            }

            Button(action: onToggleLike) {
                if song.liked {
                    Label("Remove from Liked", systemImage: "heart.slash")
                } else {
                    Label("Add to Liked", systemImage: "heart")
                }
            }

            Divider()

            if song.artistsText != nil {
                Button(action: onGoToArtist) {
                    Label("Go to Artist", systemImage: "person")
                }
            }

            if song.albumName != nil {
                Button(action: onGoToAlbum) {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }

            Divider()

            Button(action: onShare) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}

// MARK: - Context Menu Modifier

struct SongContextMenuModifier: ViewModifier {
    let song: Song
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager
    @StateObject private var downloadManager = DownloadManager.shared

    @State private var showAddToPlaylist = false
    @State private var showShareSheet = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button(action: playNext) {
                    Label("Play Next", systemImage: "text.insert")
                }

                Button(action: addToQueue) {
                    Label("Add to Queue", systemImage: "text.append")
                }

                Divider()

                // Download option
                if downloadManager.isDownloaded(song.id) {
                    Button(role: .destructive, action: deleteDownload) {
                        Label("Remove Download", systemImage: "trash")
                    }
                } else {
                    Button(action: download) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }

                Button(action: { showAddToPlaylist = true }) {
                    Label("Add to Playlist", systemImage: "plus.rectangle.on.folder")
                }

                Button(action: toggleLike) {
                    if song.liked {
                        Label("Remove from Liked", systemImage: "heart.slash")
                    } else {
                        Label("Add to Liked", systemImage: "heart")
                    }
                }

                Divider()

                Button(action: { showShareSheet = true }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            .sheet(isPresented: $showAddToPlaylist) {
                AddToPlaylistSheet(song: song)
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = URL(string: "https://music.youtube.com/watch?v=\(song.id)") {
                    ShareSheet(items: [url])
                }
            }
    }

    private func playNext() {
        queueManager.insertNext(song)
    }

    private func addToQueue() {
        queueManager.addToQueue(song)
    }

    private func toggleLike() {
        Task {
            await libraryManager.toggleLike(song: song)
        }
    }

    private func download() {
        Task {
            await downloadManager.download(song: song)
        }
    }

    private func deleteDownload() {
        downloadManager.deleteDownload(songId: song.id)
    }
}

extension View {
    func songContextMenu(song: Song) -> some View {
        modifier(SongContextMenuModifier(song: song))
    }
}

// MARK: - Add to Playlist Sheet

struct AddToPlaylistSheet: View {
    let song: Song
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var libraryManager: LibraryManager

    @State private var showCreatePlaylist = false

    var body: some View {
        NavigationStack {
            List {
                Button(action: { showCreatePlaylist = true }) {
                    Label("Create New Playlist", systemImage: "plus")
                }

                ForEach(libraryManager.playlists) { playlist in
                    Button(action: {
                        addToPlaylist(playlist)
                    }) {
                        HStack {
                            AsyncImage(url: URL(string: playlist.thumbnailUrl ?? "")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .frame(width: 40, height: 40)
                            .cornerRadius(4)

                            Text(playlist.name)

                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCreatePlaylist) {
                CreatePlaylistWithSongSheet(song: song) {
                    dismiss()
                }
            }
        }
    }

    private func addToPlaylist(_ playlist: Playlist) {
        Task {
            await libraryManager.addSongToPlaylist(song, playlist: playlist)
            dismiss()
        }
    }
}

// MARK: - Create Playlist with Song Sheet

struct CreatePlaylistWithSongSheet: View {
    let song: Song
    let onComplete: () -> Void

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var libraryManager: LibraryManager

    @State private var playlistName = ""

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
                        createPlaylist()
                    }
                    .disabled(playlistName.isEmpty)
                }
            }
        }
    }

    private func createPlaylist() {
        Task {
            let playlist = await libraryManager.createLocalPlaylist(name: playlistName)
            await libraryManager.addSongToPlaylist(song, playlist: playlist)
            dismiss()
            onComplete()
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
