import SwiftUI

struct SearchView: View {
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager

    @State private var searchQuery: String = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching: Bool = false
    @State private var selectedFilter: SearchFilter = .all

    private let ytMusic = YouTubeMusic.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search field
                VibesSearchBar(text: $searchQuery)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .onChange(of: searchQuery) { _, newValue in
                        if !newValue.isEmpty {
                            performSearch()
                        } else {
                            searchResults = []
                        }
                    }

                // Search filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        FilterChip(title: "All", isSelected: selectedFilter == .all) {
                            selectedFilter = .all
                            performSearch()
                        }
                        FilterChip(title: "Songs", isSelected: selectedFilter == .songs) {
                            selectedFilter = .songs
                            performSearch()
                        }
                        FilterChip(title: "Albums", isSelected: selectedFilter == .albums) {
                            selectedFilter = .albums
                            performSearch()
                        }
                        FilterChip(title: "Artists", isSelected: selectedFilter == .artists) {
                            selectedFilter = .artists
                            performSearch()
                        }
                        FilterChip(title: "Playlists", isSelected: selectedFilter == .playlists) {
                            selectedFilter = .playlists
                            performSearch()
                        }
                    }
                    .padding()
                }

                // Results
                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchQuery.isEmpty {
                    SearchHistoryView(onSelect: { query in
                        searchQuery = query
                        performSearch()
                    })
                } else if searchResults.isEmpty {
                    Text("No results found")
                        .foregroundColor(VibesColors.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(searchResults.enumerated()), id: \.offset) { index, result in
                                SearchResultView(result: result, onSongTap: handleResultTap)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(VibesColors.card)
                                    .cornerRadius(VibesRadius.row)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 140)
                    }
                }
            }
            .vibesBackground()
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    @State private var searchTask: Task<Void, Never>?

    private func performSearch() {
        searchTask?.cancel()
        guard !searchQuery.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }

            do {
                let results = try await ytMusic.search(query: searchQuery, filter: selectedFilter)
                if !Task.isCancelled {
                    searchResults = results
                    libraryManager.addSearchHistory(query: searchQuery)
                }
            } catch {
                if !Task.isCancelled {
                    dlog("Search failed: \(error)")
                }
            }
            if !Task.isCancelled {
                isSearching = false
            }
        }
    }

    private func handleResultTap(_ result: SearchResult) {
        Task {
            switch result {
            case .song(let song):
                dlog("🎵 [Search] Tapped song: \(song.title) (id: \(song.id))")
                if let dbSong = await libraryManager.getSong(id: song.id) {
                    dlog("🎵 [Search] Found existing song in DB, playing...")
                    await queueManager.setQueue([dbSong])
                } else {
                    dlog("🎵 [Search] Song not in DB, saving first...")
                    await libraryManager.saveSong(song)
                    if let dbSong = await libraryManager.getSong(id: song.id) {
                        dlog("🎵 [Search] Saved and retrieved song, playing...")
                        await queueManager.setQueue([dbSong])
                    } else {
                        dlog("❌ [Search] Failed to retrieve song after saving!")
                    }
                }

            case .album(let album):
                do {
                    let (_, songs) = try await ytMusic.getAlbum(browseId: album.id)
                    for song in songs {
                        await libraryManager.saveSong(song)
                    }
                    let dbSongs = await loadSongs(ids: songs.map { $0.id })
                    await queueManager.setQueue(dbSongs)
                } catch {
                    dlog("Failed to load album: \(error)")
                }

            case .playlist(let playlist):
                do {
                    let (_, songs) = try await ytMusic.getPlaylist(browseId: playlist.id)
                    for song in songs {
                        await libraryManager.saveSong(song)
                    }
                    let dbSongs = await loadSongs(ids: songs.map { $0.id })
                    await queueManager.setQueue(dbSongs)
                } catch {
                    dlog("Failed to load playlist: \(error)")
                }

            case .artist:
                break
            }
        }
    }

    private func loadSongs(ids: [String]) async -> [Song] {
        var songs: [Song] = []
        for id in ids {
            if let song = await libraryManager.getSong(id: id) {
                songs.append(song)
            }
        }
        return songs
    }
}

// MARK: - Search Result View with Navigation

struct SearchResultView: View {
    let result: SearchResult
    let onSongTap: (SearchResult) -> Void

    var body: some View {
        switch result {
        case .song(let ytSong):
            SearchSongRow(ytSong: ytSong, onTap: { onSongTap(result) })

        case .album(let album):
            NavigationLink(destination: AlbumDetailView(album: album)) {
                SearchResultRowContent(result: result)
            }

        case .artist(let artist):
            NavigationLink(destination: ArtistDetailView(artist: artist)) {
                SearchResultRowContent(result: result)
            }

        case .playlist(let playlist):
            NavigationLink(destination: YTPlaylistDetailView(ytPlaylist: playlist)) {
                SearchResultRowContent(result: result)
            }
        }
    }
}

struct SearchResultRowContent: View {
    let result: SearchResult

    var body: some View {
        HStack(spacing: 12) {
            VibesArtwork(url: thumbnailUrl, size: 56, radius: resultType == "Artist" ? 28 : 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(VibesColors.textPrimary)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(VibesColors.textSecondary)
                    .lineLimit(1)

                Text(resultType)
                    .font(.caption2)
                    .foregroundColor(VibesColors.textTertiary)
            }

            Spacer()

            Image(systemName: resultType == "Song" ? "play.circle" : "chevron.right")
                .font(.title3)
                .foregroundColor(resultType == "Song" ? VibesColors.accent : VibesColors.textTertiary)
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch result {
        case .song(let song): return song.title
        case .album(let album): return album.title
        case .artist(let artist): return artist.name
        case .playlist(let playlist): return playlist.name
        }
    }

    private var subtitle: String {
        switch result {
        case .song(let song): return song.artists
        case .album(let album): return album.artists
        case .artist: return "Artist"
        case .playlist(let playlist): return playlist.author ?? "Playlist"
        }
    }

    private var thumbnailUrl: String {
        switch result {
        case .song(let song): return song.thumbnailUrl ?? ""
        case .album(let album): return album.thumbnailUrl ?? ""
        case .artist(let artist): return artist.thumbnailUrl ?? ""
        case .playlist(let playlist): return playlist.thumbnailUrl ?? ""
        }
    }

    private var resultType: String {
        switch result {
        case .song: return "Song"
        case .album: return "Album"
        case .artist: return "Artist"
        case .playlist: return "Playlist"
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? VibesColors.accent : VibesColors.elevated)
                .foregroundColor(isSelected ? .black : VibesColors.textPrimary)
                .cornerRadius(20)
        }
    }
}

// MARK: - Search History View

struct SearchHistoryView: View {
    let onSelect: (String) -> Void
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !libraryManager.searchHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Searches")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(VibesColors.textPrimary)

                            Spacer()

                            Button("Clear") {
                                libraryManager.clearSearchHistory()
                            }
                            .font(.caption)
                            .foregroundColor(VibesColors.accent)
                        }

                        ForEach(libraryManager.searchHistory.prefix(10), id: \.id) { history in
                            Button(action: { onSelect(history.query) }) {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundColor(VibesColors.textSecondary)

                                    Text(history.query)
                                        .foregroundColor(VibesColors.textPrimary)

                                    Spacer()

                                    Image(systemName: "arrow.up.left")
                                        .font(.caption)
                                        .foregroundColor(VibesColors.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !libraryManager.recentlyPlayed.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recently Played")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(VibesColors.textPrimary)

                        ForEach(libraryManager.recentlyPlayed.prefix(10)) { song in
                            Button(action: {
                                Task {
                                    await queueManager.setQueue([song])
                                }
                            }) {
                                VibesTrackRow(song: song)
                            }
                            .buttonStyle(.plain)
                            .songContextMenu(song: song)
                        }
                    }
                }

                Spacer(minLength: 120)
            }
            .padding()
        }
    }
}

// MARK: - Search Song Row with Download

struct SearchSongRow: View {
    let ytSong: YTSong
    let onTap: () -> Void

    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager
    @State private var song: Song?
    @State private var showAddToPlaylist = false
    @State private var showShareSheet = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VibesArtwork(url: ytSong.thumbnailUrl, size: 56, radius: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(ytSong.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(VibesColors.textPrimary)
                        .lineLimit(2)

                    Text(ytSong.artists)
                        .font(.caption)
                        .foregroundColor(VibesColors.textSecondary)
                        .lineLimit(1)

                    Text("Song")
                        .font(.caption2)
                        .foregroundColor(VibesColors.textTertiary)
                }

                Spacer()

                if let song = song {
                    DownloadStatusIndicator(songId: song.id)
                        .padding(.trailing, 8)
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
