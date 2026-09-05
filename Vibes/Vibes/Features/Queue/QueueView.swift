import SwiftUI

struct QueueView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var playerManager: PlayerManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if queueManager.queue.isEmpty {
                        VibesEmptyState(
                            icon: "music.note.list",
                            title: "No Songs in Queue",
                            subtitle: "Play a song to see it here"
                        )
                    } else {
                        if queueManager.currentIndex > 0 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Historial (\(queueManager.currentIndex))")
                                    .font(.headline)
                                    .foregroundColor(VibesColors.textPrimary)
                                    .padding(.horizontal)
                                LazyVStack(spacing: 4) {
                                    ForEach(Array(queueManager.queue[0..<queueManager.currentIndex].enumerated()), id: \.element.id) { index, song in
                                        Button(action: {
                                            Task {
                                                await queueManager.playAt(index: index)
                                            }
                                        }) {
                                            QueueSongRow(
                                                song: song,
                                                isCurrentSong: false,
                                                onTap: {},
                                                onRemove: {
                                                    queueManager.removeFromQueue(at: index)
                                                }
                                            )
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(VibesColors.card)
                                            .cornerRadius(VibesRadius.row)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sonando ahora")
                                .font(.headline)
                                .foregroundColor(VibesColors.textPrimary)
                                .padding(.horizontal)
                            if queueManager.currentIndex >= 0 && queueManager.currentIndex < queueManager.queue.count {
                                QueueSongRow(
                                    song: queueManager.queue[queueManager.currentIndex],
                                    isCurrentSong: true,
                                    onTap: {}
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(VibesColors.accentDim)
                                .cornerRadius(VibesRadius.row)
                                .padding(.horizontal)
                            }
                        }

                        if queueManager.currentIndex + 1 < queueManager.queue.count {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("A continuación (\(queueManager.queue.count - queueManager.currentIndex - 1))")
                                    .font(.headline)
                                    .foregroundColor(VibesColors.textPrimary)
                                    .padding(.horizontal)
                                LazyVStack(spacing: 4) {
                                    ForEach(Array(queueManager.queue[(queueManager.currentIndex + 1)...].enumerated()), id: \.element.id) { index, song in
                                        let actualIndex = queueManager.currentIndex + 1 + index
                                        Button(action: {
                                            Task {
                                                await queueManager.playAt(index: actualIndex)
                                            }
                                        }) {
                                            QueueSongRow(
                                                song: song,
                                                isCurrentSong: false,
                                                onTap: {},
                                                onRemove: {
                                                    queueManager.removeFromQueue(at: actualIndex)
                                                }
                                            )
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(VibesColors.card)
                                            .cornerRadius(VibesRadius.row)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                    }
                    Spacer(minLength: 60)
                }
                .padding(.top)
            }
            .vibesBackground()
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Listo") {
                        dismiss()
                    }
                    .foregroundColor(VibesColors.accent)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: {
                            queueManager.toggleShuffle()
                        }) {
                            Label(
                                playerManager.isShuffleEnabled ? "Disable Shuffle" : "Enable Shuffle",
                                systemImage: "shuffle"
                            )
                        }

                        Button(role: .destructive, action: {
                            queueManager.clearQueue()
                        }) {
                            Label("Clear Queue", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(VibesColors.textPrimary)
                    }
                }
            }
        }
    }
}

struct QueueSongRow: View {
    let song: Song
    let isCurrentSong: Bool
    let onTap: () -> Void
    var onRemove: (() -> Void)? = nil

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VibesArtwork(url: song.thumbnailUrl, size: 48, radius: 8)
                    .overlay(
                        isCurrentSong ?
                        RoundedRectangle(cornerRadius: 8)
                            .fill(VibesColors.accent.opacity(0.3))
                        : nil
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.body)
                        .fontWeight(isCurrentSong ? .semibold : .regular)
                        .foregroundColor(isCurrentSong ? VibesColors.accent : VibesColors.textPrimary)
                        .lineLimit(1)

                    Text(song.artistsText ?? "Unknown Artist")
                        .font(.caption)
                        .foregroundColor(VibesColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if isCurrentSong {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(VibesColors.accent)
                } else {
                    DownloadStatusIndicator(songId: song.id)
                }
            }
        }
        .buttonStyle(.plain)
        .songContextMenu(song: song)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let onRemove = onRemove {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}
