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
                Label("Reproducir siguiente", systemImage: "text.insert")
            }

            Button(action: onAddToQueue) {
                Label("Añadir a la cola", systemImage: "text.append")
            }

            Divider()

            Button(action: onAddToPlaylist) {
                Label("Añadir a playlist", systemImage: "plus.rectangle.on.folder")
            }

            Button(action: onToggleLike) {
                if song.liked {
                    Label("Quitar de Me gusta", systemImage: "heart.slash")
                } else {
                    Label("Añadir a Me gusta", systemImage: "heart")
                }
            }

            Divider()

            if song.artistsText != nil {
                Button(action: onGoToArtist) {
                    Label("Ir al artista", systemImage: "person")
                }
            }

            if song.albumName != nil {
                Button(action: onGoToAlbum) {
                    Label("Ir al álbum", systemImage: "square.stack")
                }
            }

            Divider()

            Button(action: onShare) {
                Label("Compartir", systemImage: "square.and.arrow.up")
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
                    Label("Reproducir siguiente", systemImage: "text.insert")
                }

                Button(action: addToQueue) {
                    Label("Añadir a la cola", systemImage: "text.append")
                }

                Divider()

                // Download option
                if downloadManager.isDownloaded(song.id) {
                    Button(role: .destructive, action: deleteDownload) {
                        Label("Eliminar descarga", systemImage: "trash")
                    }
                } else {
                    Button(action: download) {
                        Label("Descargar", systemImage: "arrow.down.circle")
                    }
                }

                Button(action: { showAddToPlaylist = true }) {
                    Label("Añadir a playlist", systemImage: "plus.rectangle.on.folder")
                }

                Button(action: toggleLike) {
                    if song.liked {
                        Label("Quitar de Me gusta", systemImage: "heart.slash")
                    } else {
                        Label("Añadir a Me gusta", systemImage: "heart")
                    }
                }

                Divider()

                Button(action: { showShareSheet = true }) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
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
                    Label("Crear lista nueva", systemImage: "plus")
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
            .navigationTitle("Añadir a playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
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
                TextField("Nombre de la lista", text: $playlistName)
            }
            .navigationTitle("Nueva lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
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
