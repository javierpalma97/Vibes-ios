import SwiftUI

struct YTPlaylistDetailView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager

    let ytPlaylist: YTPlaylist

    @State private var songs: [YTSong] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    private let ytMusic = YouTubeMusic.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header actions
                if !songs.isEmpty {
                    HStack(spacing: 12) {
                        Button(action: {
                            Task {
                                await playAll()
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
                                await shuffleAll()
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

                    Button(action: {
                        Task {
                            await downloadAll()
                        }
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.down.circle")
                            Text("Download All")
                            Spacer()
                        }
                        .foregroundColor(VibesColors.accent)
                    }
                    .padding(.horizontal)
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 40)
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                Text("\(songs.count) songs")
                    .font(.subheadline)
                    .foregroundColor(VibesColors.textSecondary)
                    .padding(.horizontal)

                // Songs list
                LazyVStack(spacing: 4) {
                    ForEach(songs.indices, id: \.self) { index in
                        YTPlaylistSongRow(
                            ytSong: songs[index],
                            onTap: {
                                Task {
                                    await playSong(at: index)
                                }
                            }
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(VibesColors.card)
                        .cornerRadius(VibesRadius.row)
                        .padding(.horizontal)
                    }
                }

                Spacer(minLength: 140)
            }
            .padding(.top)
        }
        .vibesBackground()
        .navigationTitle(ytPlaylist.name)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadPlaylist()
        }
    }

    private func loadPlaylist() async {
        isLoading = true
        errorMessage = nil

        do {
            dlog("🎵 [Playlist] Loading playlist: \(ytPlaylist.id)")
            await MainActor.run { DebugLogger.shared.log("🎵 detalle playlist start id=\(ytPlaylist.id) nombre=\(ytPlaylist.name)") }

            // Solo es radio si el id NO es navegable (RD...). Las cards (charts etc.)
            // traen playlistId del botón play pero se ABREN por browse (VL...).
            let id = ytPlaylist.id
            let isBrowsable = id.hasPrefix("VL") || id.hasPrefix("PL") || id.hasPrefix("OLAK")
                || id.hasPrefix("FEmusic_") || id == "VLLM" || id == "SE"
                || id.hasPrefix("MPREb_") || id.hasPrefix("MPSP") || id.hasPrefix("UC")
            // Check if this is a radio/mix playlist
            if let playlistId = ytPlaylist.playlistId, !isBrowsable {
                // Radio playlist - use next endpoint with playlistId
                dlog("🎵 [Playlist] Radio playlist detected, using playlistId: \(playlistId)")
                songs = try await ytMusic.getRadioPlaylist(playlistId: playlistId)
                dlog("🎵 [Playlist] Loaded \(songs.count) radio songs")
            } else if ytPlaylist.id.hasPrefix("RD") {
                // Radio playlist without explicit playlistId - use the id
                dlog("🎵 [Playlist] Radio playlist (from RD prefix), using id as playlistId")
                songs = try await ytMusic.getRadioPlaylist(playlistId: ytPlaylist.id)
                dlog("🎵 [Playlist] Loaded \(songs.count) radio songs")
            } else {
                // Regular playlist - use browse endpoint (VL requerido por el servidor)
                let browseId = isBrowsable ? id : "VL\(id)"
                dlog("🎵 [Playlist] Regular playlist, using browseId: \(browseId)")
                let (_, fetchedSongs) = try await ytMusic.getPlaylist(browseId: browseId)
                songs = fetchedSongs
                dlog("🎵 [Playlist] Loaded \(songs.count) songs")
                await MainActor.run { DebugLogger.shared.log("🎵 detalle playlist OK id=\(ytPlaylist.id) songs=\(songs.count)") }
                // Persistir el conteo para que la lista muestre N canciones sin reabrir
                if !songs.isEmpty {
                    let updated = YTPlaylist(
                        id: ytPlaylist.id,
                        name: ytPlaylist.name,
                        author: ytPlaylist.author,
                        thumbnailUrl: ytPlaylist.thumbnailUrl,
                        songCount: songs.count,
                        playlistId: ytPlaylist.playlistId
                    )
                    await libraryManager.savePlaylist(updated)
                }
            }
        } catch {
            dlog("❌ [Playlist] Error loading playlist: \(error)")
            await MainActor.run { DebugLogger.shared.log("❌ detalle playlist id=\(ytPlaylist.id) err=\(error)") }
            errorMessage = "Failed to load playlist"
        }

        isLoading = false
    }

    private func playAll() async {
        guard !songs.isEmpty else { return }

        // Save all songs to database
        for ytSong in songs {
            await libraryManager.saveSong(ytSong)
        }

        // Get all songs from database
        var dbSongs: [Song] = []
        for ytSong in songs {
            if let song = await libraryManager.getSong(id: ytSong.id) {
                dbSongs.append(song)
            }
        }

        // Play the queue
        await queueManager.setQueue(dbSongs)
    }

    private func shuffleAll() async {
        guard !songs.isEmpty else { return }

        // Save all songs to database
        for ytSong in songs {
            await libraryManager.saveSong(ytSong)
        }

        // Get all songs from database
        var dbSongs: [Song] = []
        for ytSong in songs {
            if let song = await libraryManager.getSong(id: ytSong.id) {
                dbSongs.append(song)
            }
        }

        // Shuffle and play the queue
        await queueManager.setQueue(dbSongs.shuffled())
    }

    private func downloadAll() async {
        guard !songs.isEmpty else { return }

        // Save all songs to database first
        for ytSong in songs {
            await libraryManager.saveSong(ytSong)
        }

        // Get all songs from database
        var dbSongs: [Song] = []
        for ytSong in songs {
            if let song = await libraryManager.getSong(id: ytSong.id) {
                dbSongs.append(song)
            }
        }

        // Download all songs
        await DownloadManager.shared.downloadMultiple(songs: dbSongs)
    }

    private func playSong(at index: Int) async {
        // Save all songs to database
        for ytSong in songs {
            await libraryManager.saveSong(ytSong)
        }

        // Get all songs from database
        var dbSongs: [Song] = []
        for ytSong in songs {
            if let song = await libraryManager.getSong(id: ytSong.id) {
                dbSongs.append(song)
            }
        }

        // Play from the selected index
        // Disable radio mode when playing from playlist - we want the full playlist, not suggestions
        await queueManager.setQueue(dbSongs, startIndex: index, enableRadio: false)
    }
}

// MARK: - YT Playlist Song Row with Download

struct YTPlaylistSongRow: View {
    let ytSong: YTSong
    let onTap: () -> Void

    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager
    @State private var song: Song?
    @State private var showAddToPlaylist = false
    @State private var showShareSheet = false

    var body: some View {
        Button(action: onTap) {
            HStack {
                VibesArtwork(url: ytSong.thumbnailUrl, size: 50, radius: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(ytSong.title)
                        .font(.body)
                        .foregroundColor(VibesColors.textPrimary)
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
