import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var playerManager: PlayerManager

    @State private var ytHistory: [HistorySection] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let ytMusic = YouTubeMusic.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                // Local Recently Played
                if !libraryManager.recentlyPlayed.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recently Played")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)

                        ForEach(libraryManager.recentlyPlayed.prefix(20)) { song in
                            Button(action: {
                                Task {
                                    await queueManager.setQueue([song])
                                }
                            }) {
                                HistorySongRow(
                                    title: song.title,
                                    artist: song.artistsText ?? "",
                                    thumbnailUrl: song.thumbnailUrl,
                                    isPlaying: playerManager.currentSong?.id == song.id
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                // YouTube Music History (if authenticated)
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 40)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)

                        Text(error)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Retry") {
                            Task {
                                await loadHistory()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else if !ytHistory.isEmpty {
                    ForEach(ytHistory.indices, id: \.self) { index in
                        HistorySectionView(section: ytHistory[index])
                    }
                }

                Spacer(minLength: 120)
            }
            .padding(.top)
        }
        .navigationTitle("History")
        .task {
            await loadHistory()
        }
    }

    private func loadHistory() async {
        isLoading = true
        errorMessage = nil

        do {
            let history = try await ytMusic.getMusicHistory()
            await MainActor.run {
                ytHistory = history
            }
        } catch InnerTubeError.notAuthenticated {
            await MainActor.run {
                errorMessage = "Sign in to YouTube Music to see your listening history"
            }
        } catch {
            dlog("❌ [History] Error loading history: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load history"
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }
}

// MARK: - History Section View

struct HistorySectionView: View {
    let section: HistorySection
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playerManager: PlayerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)

            ForEach(section.songs.indices, id: \.self) { index in
                let song = section.songs[index]
                Button(action: {
                    Task {
                        await libraryManager.saveSong(song)
                        if let librarySong = await libraryManager.getSong(id: song.id) {
                            await queueManager.setQueue([librarySong])
                        }
                    }
                }) {
                    HistorySongRow(
                        title: song.title,
                        artist: song.artists,
                        thumbnailUrl: song.thumbnailUrl,
                        isPlaying: playerManager.currentSong?.id == song.id
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - History Song Row

struct HistorySongRow: View {
    let title: String
    let artist: String
    let thumbnailUrl: String?
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: thumbnailUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 56, height: 56)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(isPlaying ? .accentColor : .primary)
                    .lineLimit(1)

                Text(artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isPlaying {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
            }

            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - History Models

struct HistorySection {
    let title: String
    let songs: [YTSong]
}
