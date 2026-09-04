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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(VibesColors.accentDim)
                            .frame(width: 56, height: 56)
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title)
                            .foregroundColor(VibesColors.accent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Downloads")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(VibesColors.textPrimary)

                        Text("\(downloadedSongs.count) songs • \(downloadManager.formattedDownloadSize)")
                            .font(.caption)
                            .foregroundColor(VibesColors.textSecondary)
                    }

                    Spacer()

                    if !downloadedSongs.isEmpty {
                        Button(action: {
                            showDeleteAllConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(VibesColors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Playback actions
                if !downloadedSongs.isEmpty {
                    HStack(spacing: 12) {
                        Button(action: {
                            Task {
                                await queueManager.setQueue(downloadedSongs, enableRadio: false)
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

                        Button(action: {
                            Task {
                                await queueManager.setQueue(downloadedSongs.shuffled(), enableRadio: false)
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
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                // Active downloads
                if !downloadingSongs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Downloading")
                            .font(.headline)
                            .foregroundColor(VibesColors.textPrimary)
                            .padding(.horizontal)

                        ForEach(downloadingSongs) { song in
                            if case .downloading(let progress) = downloadManager.downloadState(for: song.id) {
                                HStack(spacing: 12) {
                                    VibesArtwork(url: song.thumbnailUrl, size: 48, radius: 8)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(song.title)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(VibesColors.textPrimary)
                                            .lineLimit(1)

                                        Text(song.artistsText ?? "Unknown Artist")
                                            .font(.caption)
                                            .foregroundColor(VibesColors.textSecondary)
                                            .lineLimit(1)

                                        ProgressView(value: progress)
                                            .progressViewStyle(.linear)
                                            .tint(VibesColors.accent)
                                    }

                                    Spacer()

                                    Button(action: {
                                        downloadManager.cancelDownload(songId: song.id)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(VibesColors.textSecondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(VibesColors.card)
                                .cornerRadius(VibesRadius.row)
                                .padding(.horizontal)
                            }
                        }
                    }
                }

                // Downloaded songs
                VStack(alignment: .leading, spacing: 8) {
                    Text("Downloaded")
                        .font(.headline)
                        .foregroundColor(VibesColors.textPrimary)
                        .padding(.horizontal)

                    if downloadedSongs.isEmpty && downloadingSongs.isEmpty {
                        VibesEmptyState(
                            icon: "arrow.down.circle",
                            title: "No downloads",
                            subtitle: "Download songs to listen offline"
                        )
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(downloadedSongs) { song in
                                Button(action: {
                                    Task {
                                        await queueManager.setQueue(downloadedSongs, startIndex: downloadedSongs.firstIndex(where: { $0.id == song.id }) ?? 0, enableRadio: false)
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
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task {
                                            downloadManager.deleteDownload(songId: song.id)
                                            await loadDownloadedSongs()
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .songContextMenu(song: song)
                            }
                        }
                    }
                }

                Spacer(minLength: 140)
            }
        }
        .vibesBackground()
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Delete all downloads?", isPresented: $showDeleteAllConfirmation, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                downloadManager.deleteAllDownloads()
                Task {
                    await loadDownloadedSongs()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove \(downloadedSongs.count) downloaded songs from your device.")
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
        let downloadedIds = downloadManager.getDownloadedSongIds()

        let songDescriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { song in
                downloadedIds.contains(song.id)
            }
        )

        if let songs = try? modelContext.fetch(songDescriptor) {
            downloadedSongs = songs
        }

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
