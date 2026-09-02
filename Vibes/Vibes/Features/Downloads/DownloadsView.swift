import SwiftUI
import SwiftData

struct DownloadsView: View {
    @EnvironmentObject var queueManager: QueueManager
    @Environment(\.modelContext) private var modelContext

    @StateObject private var downloadManager = DownloadManager.shared

    @State private var downloadedSongs: [Song] = []
    @State private var downloadingSongs: [Song] = []
    @State private var showDeleteAllConfirmation: Bool = false

    var body: some View {
        List {
            // Header with stats
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Descargas")
                            .font(.headline)

                        Text("\(downloadedSongs.count) canciones • \(downloadManager.formattedDownloadSize)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 8)
            }

            // Playback actions
            if !downloadedSongs.isEmpty {
                Section {
                    HStack(spacing: 16) {
                        Button(action: {
                            Task {
                                await queueManager.setQueue(downloadedSongs, enableRadio: false)
                            }
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Reproducir")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }

                        Button(action: {
                            Task {
                                await queueManager.setQueue(downloadedSongs.shuffled(), enableRadio: false)
                            }
                        }) {
                            HStack {
                                Image(systemName: "shuffle")
                                Text("Mezclar")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            // Active downloads
            if !downloadingSongs.isEmpty {
                Section(header: Text("Descargando")) {
                    ForEach(downloadingSongs) { song in
                        if case .downloading(let progress) = downloadManager.downloadState(for: song.id) {
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
                                        .lineLimit(1)

                                    Text(song.artistsText ?? "Artista desconocido")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)

                                    ProgressView(value: progress)
                                        .progressViewStyle(.linear)
                                        .tint(.green)
                                }

                                Spacer()

                                Button(action: {
                                    downloadManager.cancelDownload(songId: song.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            // Downloaded songs
            Section(header: Text("Canciones descargadas")) {
                if downloadedSongs.isEmpty && downloadingSongs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No hay descargas")
                            .font(.headline)

                        Text("Descarga canciones para escucharlas sin conexión")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(downloadedSongs) { song in
                        Button(action: {
                            Task {
                                await queueManager.setQueue(downloadedSongs, startIndex: downloadedSongs.firstIndex(where: { $0.id == song.id }) ?? 0, enableRadio: false)
                            }
                        }) {
                            SongRow(song: song)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task {
                                    downloadManager.deleteDownload(songId: song.id)
                                    await loadDownloadedSongs()
                                }
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                        .songContextMenu(song: song)
                    }
                }
            }
        }
        .navigationTitle("Descargas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !downloadedSongs.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showDeleteAllConfirmation = true
                    }) {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .confirmationDialog("¿Eliminar todas las descargas?", isPresented: $showDeleteAllConfirmation, titleVisibility: .visible) {
            Button("Eliminar todo", role: .destructive) {
                downloadManager.deleteAllDownloads()
                Task {
                    await loadDownloadedSongs()
                }
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Se eliminarán \(downloadedSongs.count) canciones descargadas de tu dispositivo.")
        }
        .task {
            await loadDownloadedSongs()
        }
        .onReceive(downloadManager.$activeDownloads) { _ in
            Task {
                await loadDownloadedSongs()
            }
        }
    }

    private func loadDownloadedSongs() async {
        // Get all downloaded songs from DownloadManager
        let downloadedIds = downloadManager.getDownloadedSongIds()

        // Fetch songs from database
        let songDescriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { song in
                downloadedIds.contains(song.id)
            }
        )

        if let songs = try? modelContext.fetch(songDescriptor) {
            downloadedSongs = songs
        }

        // Get active downloads (songs currently downloading)
        let downloadingIds = downloadManager.activeDownloads.compactMap { (songId, state) -> String? in
            if case .downloading = state {
                return songId
            }
            return nil
        }

        if !downloadingIds.isEmpty {
            let downloadingDescriptor = FetchDescriptor<Song>(
                predicate: #Predicate<Song> { song in
                    downloadingIds.contains(song.id)
                }
            )

            if let songs = try? modelContext.fetch(downloadingDescriptor) {
                downloadingSongs = songs
            }
        } else {
            downloadingSongs = []
        }
    }
}