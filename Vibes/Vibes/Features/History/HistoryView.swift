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
                if !libraryManager.recentlyPlayed.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Escuchadas recientemente")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(VibesColors.textPrimary)
                            .padding(.horizontal)

                        LazyVStack(spacing: 4) {
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
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(VibesColors.card)
                                    .cornerRadius(VibesRadius.row)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                            }
                        }
                    }
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 40)
                } else if let error = errorMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.largeTitle)
                            .foregroundColor(VibesColors.textTertiary)

                        Text(error)
                            .foregroundColor(VibesColors.textSecondary)
                            .multilineTextAlignment(.center)

                        Button("Reintentar") {
                            Task {
                                await loadHistory()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VibesColors.accent)
                        .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else if !ytHistory.isEmpty {
                    ForEach(ytHistory.indices, id: \.self) { index in
                        HistorySectionView(section: ytHistory[index])
                    }
                }

                Spacer(minLength: 140)
            }
            .padding(.top)
        }
        .vibesBackground()
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(VibesColors.textPrimary)
                .padding(.horizontal)

            LazyVStack(spacing: 4) {
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
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

// MARK: - History Song Row

struct HistorySongRow: View {
    let title: String
    let artist: String
    let thumbnailUrl: String?
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            VibesArtwork(url: thumbnailUrl, size: 56, radius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(isPlaying ? VibesColors.accent : VibesColors.textPrimary)
                    .lineLimit(1)

                Text(artist)
                    .font(.caption)
                    .foregroundColor(VibesColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if isPlaying {
                Image(systemName: "waveform")
                    .foregroundColor(VibesColors.accent)
            }
        }
    }
}

// MARK: - History Models

struct HistorySection {
    let title: String
    let songs: [YTSong]
}
