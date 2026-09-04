import SwiftUI

struct HomeView: View {
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playerManager: PlayerManager

    @State private var homePage: HomePage?
    @State private var explorePage: ExplorePage?
    @State private var isLoading: Bool = true
    @State private var isLoadingMore: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var selectedChip: HomeChip?
    @State private var previousHomePage: HomePage?
    @State private var errorMessage: String?

    private let ytMusic = YouTubeMusic.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    // Quick Access Buttons (only when no chip selected)
                    if selectedChip == nil {
                        QuickAccessSection()
                    }

                    // Quick Picks (from most played albums in last 2 weeks - matching Android)
                    if !libraryManager.quickPicks.isEmpty && selectedChip == nil {
                        QuickPicksSection(songs: libraryManager.quickPicks)
                    }

                    // Filter chips
                    if let chips = homePage?.chips, !chips.isEmpty {
                        ChipsRow(chips: chips, selectedChip: selectedChip) { chip in
                            Task {
                                await toggleChip(chip)
                            }
                        }
                    }

                    // Error state
                    if let errorMessage = errorMessage, homePage?.sections.isEmpty ?? true {
                        ErrorView(message: errorMessage) {
                            Task {
                                await loadHome()
                            }
                        }
                    }

                    // Home sections
                    if let sections = homePage?.sections {
                        ForEach(sections.indices, id: \.self) { index in
                            HomeSectionView(section: sections[index])
                        }
                    }

                    // Mood and Genres (only when no chip selected)
                    if selectedChip == nil, let genres = explorePage?.moodAndGenres, !genres.isEmpty {
                        MoodAndGenresSection(genres: genres)
                    }

                    // Loading indicator for initial load
                    if isLoading && homePage == nil {
                        LoadingView()
                    }

                    // Loading indicator for more content
                    if isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    }

                    // Infinite scroll trigger
                    if let continuation = homePage?.continuation, !isLoadingMore {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task {
                                    await loadMoreContent(continuation: continuation)
                                }
                            }
                    }

                    // Bottom spacer for mini player
                    Spacer(minLength: 120)
                }
                .padding(.top)
            }
            .refreshable {
                await refresh()
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: AccountView()) {
                        Image(systemName: "person.circle")
                            .font(.title2)
                    }
                }
            }
            .task {
                await loadHome()
                await loadExplore()
            }
        }
    }

    // MARK: - Data Loading

    private func loadHome(params: String? = nil) async {
        isLoading = true
        errorMessage = nil

        do {
            let page = try await ytMusic.getHome(params: params)
            await MainActor.run {
                if params == nil && selectedChip == nil {
                    // Initial load or refresh - replace entirely
                    homePage = page
                } else {
                    // Chip filter - keep chips but update sections
                    homePage = HomePage(
                        chips: homePage?.chips ?? page.chips,
                        sections: page.sections,
                        continuation: page.continuation
                    )
                }
            }
            dlog("🏠 [Home] Loaded \(page.sections.count) sections")
        } catch {
            dlog("❌ [Home] Error loading home feed: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load home feed"
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    private func loadExplore() async {
        do {
            let page = try await ytMusic.getExplore()
            await MainActor.run {
                explorePage = page
            }
            dlog("🎨 [Explore] Loaded \(page.moodAndGenres.count) mood & genres")
        } catch {
            dlog("❌ [Explore] Error loading explore: \(error)")
        }
    }

    private func loadMoreContent(continuation: String) async {
        guard !isLoadingMore else { return }

        await MainActor.run {
            isLoadingMore = true
        }

        do {
            let page = try await ytMusic.getHome(continuation: continuation)
            await MainActor.run {
                // Append new sections to existing ones
                let existingSections = homePage?.sections ?? []
                homePage = HomePage(
                    chips: homePage?.chips ?? [],
                    sections: existingSections + page.sections,
                    continuation: page.continuation
                )
            }
            dlog("🏠 [Home] Loaded \(page.sections.count) more sections")
        } catch {
            dlog("❌ [Home] Error loading more content: \(error)")
        }

        await MainActor.run {
            isLoadingMore = false
        }
    }

    private func toggleChip(_ chip: HomeChip) async {
        if chip == selectedChip {
            // Deselect chip - restore previous home page
            await MainActor.run {
                homePage = previousHomePage
                previousHomePage = nil
                selectedChip = nil
            }
        } else {
            // Select new chip
            if selectedChip == nil {
                // Save current state before filtering
                await MainActor.run {
                    previousHomePage = homePage
                }
            }

            await MainActor.run {
                selectedChip = chip
            }

            // Load filtered content
            await loadHome(params: chip.params)
        }
    }

    private func refresh() async {
        isRefreshing = true
        selectedChip = nil
        previousHomePage = nil

        await loadHome()
        await loadExplore()

        isRefreshing = false
    }
}

// MARK: - Quick Picks Section

struct QuickPicksSection: View {
    let songs: [Song]
    @EnvironmentObject var queueManager: QueueManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Picks")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button(action: {
                    Task {
                        await queueManager.setQueue(songs.shuffled())
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "shuffle")
                        Text("Shuffle")
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)

            // Grid layout for quick picks
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
                ForEach(songs.prefix(8)) { song in
                    QuickPickRow(song: song)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct QuickPickRow: View {
    let song: Song
    @EnvironmentObject var queueManager: QueueManager

    var body: some View {
        Button(action: {
            Task {
                await queueManager.setQueue([song])
            }
        }) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: song.thumbnailUrl ?? "")) { image in
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
                    Text(song.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(song.artistsText ?? "Unknown Artist")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .songContextMenu(song: song)
    }
}

// MARK: - Recently Played Section

struct RecentlyPlayedSection: View {
    let songs: [Song]
    @EnvironmentObject var queueManager: QueueManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Played")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(songs) { song in
                        LocalSongCard(song: song)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Chips Row

struct ChipsRow: View {
    let chips: [HomeChip]
    let selectedChip: HomeChip?
    let onSelect: (HomeChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(chips.indices, id: \.self) { index in
                    let chip = chips[index]
                    ChipView(
                        chip: chip,
                        isSelected: selectedChip?.title == chip.title
                    ) {
                        onSelect(chip)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Chip View

struct ChipView: View {
    let chip: HomeChip
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(chip.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

// MARK: - Home Section View

struct HomeSectionView: View {
    let section: HomeSection
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 12) {
                if let thumbnail = section.thumbnail {
                    AsyncImage(url: URL(string: thumbnail)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let label = section.label {
                        Text(label)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if section.browseId != nil {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding(.horizontal)

            // Section items
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(section.items.indices, id: \.self) { index in
                        HomeItemView(item: section.items[index])
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Home Item View

struct HomeItemView: View {
    let item: HomeItem
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager

    var body: some View {
        switch item {
        case .song(let song):
            SongCard(ytSong: song)
        case .album(let album):
            NavigationLink(destination: AlbumDetailView(album: album)) {
                AlbumCard(album: album)
            }
        case .artist(let artist):
            NavigationLink(destination: ArtistDetailView(artist: artist)) {
                ArtistCard(artist: artist)
            }
        case .playlist(let playlist):
            NavigationLink(destination: YTPlaylistDetailView(ytPlaylist: playlist)) {
                PlaylistCard(ytPlaylist: playlist)
            }
        }
    }
}

// MARK: - Mood and Genres Section

struct MoodAndGenresSection: View {
    let genres: [MoodAndGenre]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mood & Genres")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                NavigationLink(destination: MoodAndGenresView()) {
                    Text("See all")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(genres.prefix(8)) { genre in
                        MoodGenreButton(genre: genre)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct MoodGenreButton: View {
    let genre: MoodAndGenre

    var body: some View {
        NavigationLink(destination: BrowseView(browseId: genre.id, params: genre.params, title: genre.title)) {
            Text(genre.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    // Title placeholder
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 150, height: 24)
                        .cornerRadius(4)
                        .padding(.horizontal)

                    // Items placeholder
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(0..<4, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 8) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 160, height: 160)
                                        .cornerRadius(12)

                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 120, height: 16)
                                        .cornerRadius(4)

                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 80, height: 12)
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text(message)
                .foregroundColor(.secondary)

            Button("Retry") {
                onRetry()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Local Song Card (for Recently Played)

struct LocalSongCard: View {
    let song: Song
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager

    var body: some View {
        Button(action: {
            Task {
                await queueManager.setQueue([song])
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: URL(string: song.thumbnailUrl ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 160, height: 160)
                .cornerRadius(12)

                Text(song.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .frame(width: 160, alignment: .leading)

                Text(song.artistsText ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .leading)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Song Card

struct SongCard: View {
    let ytSong: YTSong
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager

    var body: some View {
        Button(action: {
            Task {
                // Save song and play it
                await libraryManager.saveSong(ytSong)
                if let song = await libraryManager.getSong(id: ytSong.id) {
                    await queueManager.setQueue([song])
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: URL(string: ytSong.thumbnailUrl ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 160, height: 160)
                .cornerRadius(12)

                Text(ytSong.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .frame(width: 160, alignment: .leading)

                Text(ytSong.artists)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .leading)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Album Card

struct AlbumCard: View {
    let album: YTAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: URL(string: album.thumbnailUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 160, height: 160)
            .cornerRadius(12)

            Text(album.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)

            Text(album.artists)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)
        }
    }
}

// MARK: - Artist Card

struct ArtistCard: View {
    let artist: YTArtist

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: URL(string: artist.thumbnailUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 160, height: 160)

            Text(artist.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)

            Text("Artist")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 160, alignment: .leading)
        }
    }
}

// MARK: - Playlist Card

struct PlaylistCard: View {
    let ytPlaylist: YTPlaylist

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: URL(string: ytPlaylist.thumbnailUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "music.note.list")
                            .foregroundColor(.white)
                    )
            }
            .frame(width: 160, height: 160)
            .cornerRadius(12)

            Text(ytPlaylist.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)

            if let author = ytPlaylist.author {
                Text(author)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .leading)
            }
        }
    }
}

// MARK: - Quick Access Section

struct QuickAccessSection: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                NavigationLink(destination: ChartsView()) {
                    QuickAccessButton(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Charts",
                        color: .orange
                    )
                }

                NavigationLink(destination: NewReleasesView()) {
                    QuickAccessButton(
                        icon: "sparkles",
                        title: "New Releases",
                        color: .purple
                    )
                }

                NavigationLink(destination: HistoryView()) {
                    QuickAccessButton(
                        icon: "clock.arrow.circlepath",
                        title: "History",
                        color: .blue
                    )
                }

                NavigationLink(destination: MoodAndGenresView()) {
                    QuickAccessButton(
                        icon: "theatermasks",
                        title: "Moods",
                        color: .green
                    )
                }

                NavigationLink(destination: StatsView()) {
                    QuickAccessButton(
                        icon: "chart.bar.fill",
                        title: "Stats",
                        color: .pink
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

struct QuickAccessButton: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(color)
                .cornerRadius(12)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .frame(width: 80)
    }
}
