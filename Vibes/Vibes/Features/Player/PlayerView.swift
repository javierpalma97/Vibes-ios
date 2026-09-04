import SwiftUI

enum PlayerBottomTab {
    case upNext
    case lyrics
}

struct PlayerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var playerManager: PlayerManager
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var lyricsManager: LyricsManager
    @EnvironmentObject var themeManager: ThemeManager

    @State private var isDraggingSlider: Bool = false
    @State private var sliderValue: Double = 0
    @State private var showQueue: Bool = false
    @State private var bottomTab: PlayerBottomTab = .upNext

    var body: some View {
        ZStack {
            VibesColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.title2)
                            .foregroundColor(VibesColors.textPrimary)
                    }
                    Spacer()
                    Menu {
                        if let song = playerManager.currentSong {
                            PlayerMenuContent(song: song)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .foregroundColor(VibesColors.textPrimary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 20) {
                        // Artwork
                        VibesArtwork(
                            url: playerManager.currentSong?.thumbnailUrl,
                            size: min(UIScreen.main.bounds.width - 120, 340),
                            radius: 20
                        )
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                        .padding(.top, 12)

                        // Title + actions
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(playerManager.currentSong?.title ?? "")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(VibesColors.textPrimary)
                                    .lineLimit(1)
                                Text(playerManager.currentSong?.artistsText ?? "")
                                    .font(.body)
                                    .foregroundColor(VibesColors.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(action: {
                                if let song = playerManager.currentSong {
                                    Task {
                                        await toggleLike(song: song)
                                    }
                                }
                            }) {
                                Image(systemName: playerManager.currentSong?.liked == true ? "heart.fill" : "heart")
                                    .font(.title2)
                                    .foregroundColor(playerManager.currentSong?.liked == true ? VibesColors.accent : VibesColors.textSecondary)
                            }
                            Button(action: {
                                showQueue = true
                            }) {
                                Image(systemName: "list.bullet")
                                    .font(.title2)
                                    .foregroundColor(VibesColors.textSecondary)
                            }
                        }
                        .padding(.horizontal, 24)

                        // Progress
                        VStack(spacing: 6) {
                            Slider(
                                value: $sliderValue,
                                in: 0...max(playerManager.duration, 1),
                                onEditingChanged: { editing in
                                    isDraggingSlider = editing
                                    if !editing {
                                        playerManager.seek(to: sliderValue)
                                    }
                                }
                            )
                            .accentColor(VibesColors.accent)

                            HStack {
                                Text(formatTime(isDraggingSlider ? sliderValue : playerManager.currentTime))
                                    .font(.caption)
                                    .foregroundColor(VibesColors.textSecondary)
                                Spacer()
                                Text(formatTime(playerManager.duration))
                                    .font(.caption)
                                    .foregroundColor(VibesColors.textSecondary)
                            }
                        }
                        .padding(.horizontal, 24)
                        .onChange(of: playerManager.currentTime) { _, newValue in
                            if !isDraggingSlider {
                                sliderValue = newValue
                            }
                        }

                        // Controls
                        HStack(spacing: 36) {
                            Button(action: {
                                queueManager.toggleShuffle()
                            }) {
                                Image(systemName: "shuffle")
                                    .font(.title2)
                                    .foregroundColor(playerManager.isShuffleEnabled ? VibesColors.accent : VibesColors.textTertiary)
                            }

                            Button(action: {
                                playerManager.playPrevious()
                            }) {
                                Image(systemName: "backward.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(VibesColors.textPrimary)
                            }

                            Button(action: {
                                playerManager.togglePlayPause()
                            }) {
                                Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 76))
                                    .foregroundColor(.white)
                            }

                            Button(action: {
                                playerManager.playNext()
                            }) {
                                Image(systemName: "forward.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(VibesColors.textPrimary)
                            }

                            Button(action: {
                                switch playerManager.repeatMode {
                                case .off:
                                    playerManager.repeatMode = .all
                                case .all:
                                    playerManager.repeatMode = .one
                                case .one:
                                    playerManager.repeatMode = .off
                                }
                            }) {
                                Image(systemName: repeatIcon)
                                    .font(.title2)
                                    .foregroundColor(playerManager.repeatMode != .off ? VibesColors.accent : VibesColors.textTertiary)
                            }
                        }
                        .padding(.vertical, 4)

                        // Secondary row
                        HStack(spacing: 28) {
                            SleepTimerButton()
                                .foregroundColor(VibesColors.textSecondary)
                            AirPlayButton()
                                .frame(width: 44, height: 44)
                            AudioOutputInfo()
                        }

                        // Bottom tabs: Up Next / Lyrics
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                PlayerBottomTabButton(
                                    title: "Up Next",
                                    icon: "list.bullet",
                                    selected: bottomTab == .upNext,
                                    action: { bottomTab = .upNext }
                                )
                                PlayerBottomTabButton(
                                    title: "Lyrics",
                                    icon: "quote.bubble",
                                    selected: bottomTab == .lyrics,
                                    action: { bottomTab = .lyrics }
                                )
                            }
                            .padding(.horizontal, 24)

                            if bottomTab == .upNext {
                                UpNextInline(onOpenQueue: { showQueue = true })
                                    .padding(.top, 8)
                            } else {
                                LyricsView()
                                    .frame(minHeight: 220)
                                    .padding(.top, 8)
                            }
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
    }

    private func toggleLike(song: Song) async {
        await libraryManager.toggleLike(song: song)
    }

    private var repeatIcon: String {
        switch playerManager.repeatMode {
        case .off:
            return "repeat"
        case .one:
            return "repeat.1"
        case .all:
            return "repeat"
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "0:00" }

        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Bottom tab button

private struct PlayerBottomTabButton: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(selected ? .semibold : .regular)
                }
                .foregroundColor(selected ? VibesColors.textPrimary : VibesColors.textSecondary)
                Rectangle()
                    .fill(selected ? VibesColors.accent : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Inline Up Next

private struct UpNextInline: View {
    @EnvironmentObject var queueManager: QueueManager
    let onOpenQueue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let upcoming = Array(queueManager.queue.dropFirst(max(queueManager.currentIndex + 1, 0)).prefix(5))
            if upcoming.isEmpty {
                Text("Queue is empty")
                    .font(.subheadline)
                    .foregroundColor(VibesColors.textSecondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { offset, song in
                    Button(action: {
                        Task {
                            await queueManager.playAt(index: queueManager.currentIndex + 1 + offset)
                        }
                    }) {
                        VibesTrackRow(song: song)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onOpenQueue) {
                    Text("Open full queue")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(VibesColors.accent)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
            }
        }
    }
}

// MARK: - Player Menu Content

struct PlayerMenuContent: View {
    let song: Song
    @StateObject private var downloadManager = DownloadManager.shared
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager

    var body: some View {
        if downloadManager.isDownloaded(song.id) {
            Button(role: .destructive) {
                downloadManager.deleteDownload(songId: song.id)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        } else {
            Button {
                Task {
                    await downloadManager.download(song: song)
                }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }

        Divider()

        Button {
            queueManager.insertNext(song)
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }

        Button {
            queueManager.addToQueue(song)
        } label: {
            Label("Add to Queue", systemImage: "text.append")
        }

        Divider()

        Button {
            Task {
                await libraryManager.toggleLike(song: song)
            }
        } label: {
            if song.liked {
                Label("Remove from Liked", systemImage: "heart.slash")
            } else {
                Label("Add to Liked", systemImage: "heart")
            }
        }

        Divider()

        if let url = URL(string: "https://music.youtube.com/watch?v=\(song.id)") {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}
