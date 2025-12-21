import SwiftUI

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
    @State private var showingLyrics: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            // Background gradient (dynamic theme)
            themeManager.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.title2)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Text("Now Playing")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    // Lyrics toggle button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingLyrics.toggle()
                        }
                    }) {
                        Image(systemName: showingLyrics ? "music.note.list" : "quote.bubble")
                            .font(.title2)
                            .foregroundColor(lyricsManager.currentLyrics != nil ? .white : .white.opacity(0.3))
                    }
                    .disabled(lyricsManager.currentLyrics == nil)

                    Menu {
                        if let song = playerManager.currentSong {
                            PlayerMenuContent(song: song)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                .padding()

                Spacer()

                // Album artwork or Lyrics view
                ZStack {
                    if showingLyrics {
                        // Lyrics view
                        LyricsView()
                            .frame(width: UIScreen.main.bounds.width - 80, height: UIScreen.main.bounds.width - 80)
                            .cornerRadius(20)
                            .transition(.opacity)
                    } else {
                        // Album artwork
                        AsyncImage(url: URL(string: playerManager.currentSong?.thumbnailUrl ?? "")) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: UIScreen.main.bounds.width - 80, height: UIScreen.main.bounds.width - 80)
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                        .transition(.opacity)
                    }
                }
                .onTapGesture {
                    // Tap artwork/lyrics to toggle
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingLyrics.toggle()
                    }
                }

                Spacer()

                // Song info
                VStack(spacing: 8) {
                    Text(playerManager.currentSong?.title ?? "")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(playerManager.currentSong?.artistsText ?? "")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.horizontal)

                // Audio output indicator
                AudioOutputInfo()
                    .padding(.bottom, 8)

                // Action buttons
                HStack(spacing: 24) {
                    // Sleep Timer
                    SleepTimerButton()
                        .foregroundColor(.white)
                        .frame(width: 44)

                    Spacer()

                    // Like button
                    Button(action: {
                        if let song = playerManager.currentSong {
                            Task {
                                await toggleLike(song: song)
                            }
                        }
                    }) {
                        Image(systemName: playerManager.currentSong?.liked == true ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundColor(playerManager.currentSong?.liked == true ? .red : .white)
                    }
                    .frame(width: 44)

                    Spacer()

                    // AirPlay button
                    AirPlayButton()
                        .frame(width: 44, height: 44)

                    Spacer()

                    // Queue button
                    Button(action: {
                        showQueue = true
                    }) {
                        Image(systemName: "list.bullet")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .frame(width: 44)
                }
                .padding(.horizontal, 32)

                // Progress slider
                VStack(spacing: 8) {
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
                    .accentColor(.white)

                    HStack {
                        Text(formatTime(isDraggingSlider ? sliderValue : playerManager.currentTime))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

                        Spacer()

                        Text(formatTime(playerManager.duration))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal)
                .onChange(of: playerManager.currentTime) { oldValue, newValue in
                    if !isDraggingSlider {
                        sliderValue = newValue
                    }
                }

                // Playback controls
                HStack(spacing: 40) {
                    // Shuffle
                    Button(action: {
                        queueManager.toggleShuffle()
                    }) {
                        Image(systemName: "shuffle")
                            .font(.title3)
                            .foregroundColor(playerManager.isShuffleEnabled ? .accentColor : .white.opacity(0.7))
                    }

                    // Previous
                    Button(action: {
                        playerManager.playPrevious()
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }

                    // Play/Pause
                    Button(action: {
                        playerManager.togglePlayPause()
                    }) {
                        Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 72))
                            .foregroundColor(.white)
                    }

                    // Next
                    Button(action: {
                        playerManager.playNext()
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }

                    // Repeat
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
                            .font(.title3)
                            .foregroundColor(playerManager.repeatMode != .off ? .accentColor : .white.opacity(0.7))
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
        }
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

// MARK: - Player Menu Content

struct PlayerMenuContent: View {
    let song: Song
    @StateObject private var downloadManager = DownloadManager.shared
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager

    var body: some View {
        // Download option
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
