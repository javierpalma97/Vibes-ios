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
                // Album Header
                AlbumHeader(
                    album: albumDetails ?? album,
                    songCount: songs.count,
                    onPlay: playAll,
                    onShuffle: shuffleAll,
                    onDownloadAll: downloadAll
                )

                // Songs List
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task {
                                await loadAlbum()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 0) {
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
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                    .padding(.top, 16)
                }

                Spacer(minLength: 120)
            }
        }
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
            print("🎵 [Album] Loading album: \(album.id)")
            let (fetchedAlbum, fetchedSongs) = try await ytMusic.getAlbum(browseId: album.id)
            print("🎵 [Album] Loaded \(fetchedSongs.count) songs")
            await MainActor.run {
                albumDetails = fetchedAlbum
                songs = fetchedSongs
            }
        } catch {
            print("❌ [Album] Error loading album: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load album"
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    private func playSong(at index: Int) async {
        // Convert all songs to library songs and set queue
        var librarySongs: [Song] = []
        for ytSong in songs {
            await libraryManager.saveSong(ytSong)
            if let song = await libraryManager.getSong(id: ytSong.id) {
                librarySongs.append(song)
            }
        }

        if !librarySongs.isEmpty {
            // Disable radio mode when playing from album - we want the full album, not suggestions
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
            // Album artwork
            AsyncImage(url: URL(string: album.thumbnailUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 240, height: 240)
            .cornerRadius(12)
            .shadow(radius: 10)

            // Album info
            VStack(spacing: 4) {
                Text(album.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(album.artists)
                    .font(.body)
                    .foregroundColor(.secondary)

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
                .foregroundColor(.secondary)
            }

            // Play buttons
            HStack(spacing: 16) {
                Button(action: onPlay) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Play")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(25)
                }

                Button(action: onShuffle) {
                    HStack {
                        Image(systemName: "shuffle")
                        Text("Shuffle")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(25)
                }
            }
            .padding(.horizontal)

            // Download All button
            Button(action: onDownloadAll) {
                HStack {
                    Image(systemName: "arrow.down.circle")
                    Text("Download All")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(UIColor.tertiarySystemBackground))
                .foregroundColor(.accentColor)
                .cornerRadius(25)
            }
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
                // Track number or playing indicator
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .frame(width: 32)
                } else {
                    Text("\(trackNumber)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 32)
                }

                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.body)
                        .foregroundColor(isPlaying ? .accentColor : .primary)
                        .lineLimit(1)

                    Text(song.artists)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Duration
                if let duration = song.duration {
                    Text(duration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // More button
                Button(action: {}) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
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
                // Track number or playing indicator
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .frame(width: 32)
                } else {
                    Text("\(trackNumber)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 32)
                }

                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(ytSong.title)
                        .font(.body)
                        .foregroundColor(isPlaying ? .accentColor : .primary)
                        .lineLimit(1)

                    Text(ytSong.artists)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Duration
                if let duration = ytSong.duration {
                    Text(duration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Download indicator
                if let song = song {
                    DownloadStatusIndicator(songId: song.id)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
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
            // Ensure song is saved to database
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
