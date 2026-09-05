import SwiftUI

struct AlbumDetailView: View {
    let album: YTAlbum

    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playerManager: PlayerManager

    @State private var songs: [YTSong] = []
    @State private var albumDetails: YTAlbum?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let ytMusic = YouTubeMusic.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AlbumHeader(
                    album: albumDetails ?? album,
                    songCount: songs.count,
                    onPlay: playAll,
                    onShuffle: shuffleAll,
                    onDownloadAll: downloadAll
                )

                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if let error = errorMessage {
                    VStack(spacing: 14) {
                        Text(error)
                            .foregroundColor(VibesColors.textSecondary)
                        Button("Reintentar") {
                            Task {
                                await loadAlbum()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VibesColors.accent)
                        .foregroundColor(.black)
                    }
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(songs.indices, id: \.self) { index in
                            AlbumSongRowWithDownload(
                                ytSong: songs[index],
                                trackNumber: index + 1,
                                isPlaying: playerManager.currentSong?.id == songs[index].id
                            ) {
                                Task {
                                    await playSong(at: index)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(VibesColors.card)
                            .cornerRadius(VibesRadius.row)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 16)
                }

                Spacer(minLength: 140)
            }
        }
        .vibesBackground()
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAlbum()
        }
    }

    private func loadAlbum() async {
        isLoading = true
        errorMessage = nil

        do {
            dlog("🎵 [Album] Loading album: \(album.id)")
            let (fetchedAlbum, fetchedSongs) = try await ytMusic.getAlbum(browseId: album.id)
            dlog("🎵 [Album] Loaded \(fetchedSongs.count) songs")
            await MainActor.run {
                albumDetails = fetchedAlbum
                songs = fetchedSongs
            }
        } catch {
            dlog("❌ [Album] Error loading album: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load album"
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    private func playSong(at index: Int) async {
        var librarySongs: [Song] = []
        for ytSong in songs {
            await libraryManager.saveSong(ytSong)
            if let song = await libraryManager.getSong(id: ytSong.id) {
                librarySongs.append(song)
            }
        }

        if !librarySongs.isEmpty {
            await queueManager.setQueue(librarySongs, startIndex: index, enableRadio: false)
        }
    }

    private func playAll() {
        Task {
            await playSong(at: 0)
        }
    }

    private func shuffleAll() {
        Task {
            var librarySongs: [Song] = []
            for ytSong in songs {
                await libraryManager.saveSong(ytSong)
                if let song = await libraryManager.getSong(id: ytSong.id) {
                    librarySongs.append(song)
                }
            }

            if !librarySongs.isEmpty {
                await queueManager.setQueue(librarySongs.shuffled())
            }
        }
    }

    private func downloadAll() {
        Task {
            var librarySongs: [Song] = []
            for ytSong in songs {
                await libraryManager.saveSong(ytSong)
                if let song = await libraryManager.getSong(id: ytSong.id) {
                    librarySongs.append(song)
                }
            }

            if !librarySongs.isEmpty {
                await DownloadManager.shared.downloadMultiple(songs: librarySongs)
            }
        }
    }
}

// MARK: - Album Header

struct AlbumHeader: View {
    let album: YTAlbum
    let songCount: Int
    let onPlay: () -> Void
    let onShuffle: () -> Void
    let onDownloadAll: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VibesArtwork(url: album.thumbnailUrl, size: 220, radius: 16)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

            VStack(spacing: 4) {
                Text(album.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(VibesColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(album.artists)
                    .font(.body)
                    .foregroundColor(VibesColors.textSecondary)

                HStack(spacing: 8) {
                    if let year = album.year {
                        Text(year)
                    }
                    if songCount > 0 {
                        Text("•")
                        Text("\(songCount) songs")
                    }
                }
                .font(.caption)
                .foregroundColor(VibesColors.textSecondary)
            }

            HStack(spacing: 12) {
                Button(action: onPlay) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Reproducir")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(VibesColors.accent)
                    .foregroundColor(.black)
                    .cornerRadius(12)
                }

                Button(action: onShuffle) {
                    HStack {
                        Image(systemName: "shuffle")
                        Text("Aleatorio")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(VibesColors.elevated)
                    .foregroundColor(VibesColors.textPrimary)
                    .cornerRadius(12)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            Button(action: onDownloadAll) {
                HStack {
                    Image(systemName: "arrow.down.circle")
                    Text("Descargar todo")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(VibesColors.card)
                .foregroundColor(VibesColors.accent)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Album Song Row

struct AlbumSongRow: View {
    let song: YTSong
    let trackNumber: Int
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(VibesColors.accent)
                        .frame(width: 32)
                } else {
                    Text("\(trackNumber)")
                        .font(.subheadline)
                        .foregroundColor(VibesColors.textSecondary)
                        .frame(width: 32)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.body)
                        .foregroundColor(isPlaying ? VibesColors.accent : VibesColors.textPrimary)
                        .lineLimit(1)

                    Text(song.artists)
                        .font(.caption)
                        .foregroundColor(VibesColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if let duration = song.duration {
                    Text(duration)
                        .font(.caption)
                        .foregroundColor(VibesColors.textSecondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Album Song Row With Download

struct AlbumSongRowWithDownload: View {
    let ytSong: YTSong
    let trackNumber: Int
    let isPlaying: Bool
    let onTap: () -> Void

    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager
    @State private var song: Song?
    @State private var showAddToPlaylist = false
    @State private var showShareSheet = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(VibesColors.accent)
                        .frame(width: 32)
                } else {
                    Text("\(trackNumber)")
                        .font(.subheadline)
                        .foregroundColor(VibesColors.textSecondary)
                        .frame(width: 32)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(ytSong.title)
                        .font(.body)
                        .foregroundColor(isPlaying ? VibesColors.accent : VibesColors.textPrimary)
                        .lineLimit(1)

                    Text(ytSong.artists)
                        .font(.caption)
                        .foregroundColor(VibesColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if let song = song {
                    DownloadStatusIndicator(songId: song.id)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let song = song {
                Button(action: { queueManager.insertNext(song) }) {
                    Label("Play Next", systemImage: "text.insert")
                }

                Button(action: { queueManager.addToQueue(song) }) {
                    Label("Add to Queue", systemImage: "text.append")
                }

                Divider()

                Button(action: { downloadSong() }) {
                    if DownloadManager.shared.isDownloaded(song.id) {
                        Label("Remove Download", systemImage: "trash")
                    } else {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }

                Button(action: { showAddToPlaylist = true }) {
                    Label("Add to Playlist", systemImage: "plus.rectangle.on.folder")
                }

                Button(action: { toggleLike() }) {
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
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let song = song {
                AddToPlaylistSheet(song: song)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let song = song {
                if let url = URL(string: "https://music.youtube.com/watch?v=\(song.id)") {
                    ShareSheet(items: [url])
                }
            }
        }
        .task {
            await libraryManager.saveSong(ytSong)
            song = await libraryManager.getSong(id: ytSong.id)
        }
    }

    private func downloadSong() {
        guard let song = song else { return }
        Task {
            if DownloadManager.shared.isDownloaded(song.id) {
                DownloadManager.shared.deleteDownload(songId: song.id)
            } else {
                await DownloadManager.shared.download(song: song)
            }
        }
    }

    private func toggleLike() {
        guard let song = song else { return }
        Task {
            await libraryManager.toggleLike(song: song)
        }
    }
}
