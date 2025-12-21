import SwiftUI

struct QueueView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var playerManager: PlayerManager

    var body: some View {
        NavigationStack {
            List {
                if !queueManager.queue.isEmpty {
                    // History - Previously played songs (chronological order, most recent at bottom)
                    if queueManager.currentIndex > 0 {
                        Section(header: Text("History (\(queueManager.currentIndex))")) {
                            ForEach(Array(queueManager.queue[0..<queueManager.currentIndex].enumerated()), id: \.element.id) { index, song in
                                QueueSongRow(
                                    song: song,
                                    isCurrentSong: false,
                                    onTap: {
                                        Task {
                                            await queueManager.playAt(index: index)
                                        }
                                    },
                                    onRemove: {
                                        queueManager.removeFromQueue(at: index)
                                    }
                                )
                            }
                        }
                    }

                    // Now Playing - Current song
                    Section(header: Text("Now Playing")) {
                        if queueManager.currentIndex >= 0 && queueManager.currentIndex < queueManager.queue.count {
                            QueueSongRow(
                                song: queueManager.queue[queueManager.currentIndex],
                                isCurrentSong: true,
                                onTap: {}
                            )
                        }
                    }

                    // Up Next - Upcoming songs
                    if queueManager.currentIndex + 1 < queueManager.queue.count {
                        Section(header: Text("Up Next (\(queueManager.queue.count - queueManager.currentIndex - 1))")) {
                            ForEach(Array(queueManager.queue[(queueManager.currentIndex + 1)...].enumerated()), id: \.element.id) { index, song in
                                let actualIndex = queueManager.currentIndex + 1 + index
                                QueueSongRow(
                                    song: song,
                                    isCurrentSong: false,
                                    onTap: {
                                        Task {
                                            await queueManager.playAt(index: actualIndex)
                                        }
                                    },
                                    onRemove: {
                                        queueManager.removeFromQueue(at: actualIndex)
                                    }
                                )
                            }
                            .onMove { source, destination in
                                // Adjust indices for the section offset
                                let adjustedSource = source.map { $0 + queueManager.currentIndex + 1 }
                                let adjustedDestination = destination + queueManager.currentIndex + 1
                                if let first = adjustedSource.first {
                                    queueManager.moveItem(from: first, to: adjustedDestination)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Songs in Queue",
                        systemImage: "music.note.list",
                        description: Text("Play a song to see it here")
                    )
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
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
                // Thumbnail
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
                .overlay(
                    isCurrentSong ?
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                        .cornerRadius(6)
                    : nil
                )

                // Song info
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.body)
                        .fontWeight(isCurrentSong ? .semibold : .regular)
                        .foregroundColor(isCurrentSong ? .accentColor : .primary)
                        .lineLimit(1)

                    Text(song.artistsText ?? "Unknown Artist")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isCurrentSong {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                } else {
                    DownloadStatusIndicator(songId: song.id)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
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
