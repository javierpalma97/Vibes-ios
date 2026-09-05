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
    @State private var showSearch = false

    private let ytMusic = YouTubeMusic.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    // Search pill
                    Button(action: { showSearch = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(VibesColors.textSecondary)
                            Text("Buscar canciones, artistas, playlists...")
                                .foregroundColor(VibesColors.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(VibesColors.elevated)
                        .cornerRadius(VibesRadius.pill)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // For You
                    if selectedChip == nil && !libraryManager.quickPicks.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            VibesSectionHeader(
                                title: "Para ti",
                                subtitle: "Listas personalizadas y novedades",
                                actionTitle: "",
                                action: nil
                            )
                            .padding(.horizontal)
                            QuickPicksCarousel(songs: libraryManager.quickPicks)
                        }
                    }

                    // Quick tiles
                    if selectedChip == nil {
                        HStack(spacing: 12) {
                            NavigationLink(destination: LikedSongsPlaylistView()) {
                                VibesQuickTileContent(icon: "heart", title: "Mis Favoritos")
                            }
                            NavigationLink(destination: HistoryView()) {
                                VibesQuickTileContent(icon: "clock.arrow.circlepath", title: "Recientes")
                            }
                            NavigationLink(destination: NewReleasesView()) {
                                VibesQuickTileContent(icon: "sparkles", title: "Novedades")
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }

                    // Recently played banners
                    if selectedChip == nil && !libraryManager.recentlyPlayed.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Escuchado recientemente")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(VibesColors.textPrimary)
                                Spacer()
                                NavigationLink(destination: HistoryView()) {
                                    Text("Ver todo")
                                        .font(.subheadline)
                                        .foregroundColor(VibesColors.accent)
                                }
                            }
                            .padding(.horizontal)
                            RecentlyPlayedCarousel(songs: Array(libraryManager.recentlyPlayed.prefix(10)))
                        }
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

                    // Mood and Genres
                    if selectedChip == nil, let genres = explorePage?.moodAndGenres, !genres.isEmpty {
                        MoodAndGenresSection(genres: genres)
                    }

                    if isLoading && homePage == nil {
                        LoadingView()
                    }

                    if isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    }

                    if let continuation = homePage?.continuation, !isLoadingMore {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task {
                                    await loadMoreContent(continuation: continuation)
                                }
                            }
                    }

                    Spacer(minLength: 140)
                }
                .padding(.top)
            }
            .vibesBackground()
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
                            .foregroundColor(VibesColors.textPrimary)
                    }
                }
            }
            .task {
                await loadHome()
                await loadExplore()
            }
            .navigationDestination(isPresented: $showSearch) {
                SearchView()
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
                    homePage = page
                } else {
                    homePage = HomePage(
                        chips: homePage?.chips ?? page.chips,
                        sections: page.sections,
                        continuation: page.continuation
                    )
                }
            }
            dlog("🏠 [Home] Loaded \(page.sections.count) sections")
        } catch {
            // Navegar rápido cancela la petición: no es un error mostrable
            if error is CancellationError {
                await MainActor.run { isLoading = false }
                return
            }
            dlog("❌ [Home] Error loading home feed: \(error)")
            await MainActor.run {
                errorMessage = "No se pudo cargar el inicio"
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
            await MainActor.run {
                homePage = previousHomePage
                previousHomePage = nil
                selectedChip = nil
            }
        } else {
            if selectedChip == nil {
                await MainActor.run {
                    previousHomePage = homePage
                }
            }

            await MainActor.run {
                selectedChip = chip
            }

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

// MARK: - Quick Picks carousel (For You cards)

struct QuickPicksCarousel: View {
    let songs: [Song]
    @EnvironmentObject var queueManager: QueueManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(songs.prefix(10)) { song in
                    Button(action: {
                        Task {
                            await queueManager.setQueue([song])
                        }
                    }) {
                        VibesPlaylistCard(
                            title: song.title,
                            subtitle: song.artistsText ?? "Unknown Artist",
                            artworkUrl: song.thumbnailUrl,
                            width: 150
                        )
                    }
                    .buttonStyle(.plain)
                    .songContextMenu(song: song)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct VibesQuickTileContent: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(VibesColors.textPrimary)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(VibesColors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(VibesColors.card)
        .cornerRadius(VibesRadius.card)
    }
}

// MARK: - Recently played banners

struct RecentlyPlayedCarousel: View {
    let songs: [Song]
    @EnvironmentObject var queueManager: QueueManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(songs) { song in
                    Button(action: {
                        Task {
                            await queueManager.setQueue([song])
                        }
                    }) {
                        ZStack(alignment: .bottomLeading) {
                            VibesArtwork(url: song.thumbnailUrl, size: 220, radius: 16)
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.75)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(width: 220, height: 220)
                            .cornerRadius(16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(song.artistsText ?? "")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                            .padding(12)
                        }
                        .frame(width: 220, height: 220)
                    }
                    .buttonStyle(.plain)
                    .songContextMenu(song: song)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Quick Picks Section (list style, reused by nobody else — kept for compat)

struct QuickPicksSection: View {
    let songs: [Song]
    @EnvironmentObject var queueManager: QueueManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Selección rápida")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(VibesColors.textPrimary)
                Spacer()
                Button(action: {
                    Task {
                        await queueManager.setQueue(songs.shuffled())
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "shuffle")
                        Text("Aleatorio")
                    }
                    .font(.subheadline)
                    .foregroundColor(VibesColors.accent)
                }
            }
            .padding(.horizontal)

            LazyVStack(spacing: 4) {
                ForEach(songs.prefix(8)) { song in
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
            VibesTrackRow(song: song)
        }
        .buttonStyle(.plain)
        .songContextMenu(song: song)
    }
}

// MARK: - Recently Played Section

struct RecentlyPlayedSection: View {
    let songs: [Song]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Escuchadas recientemente")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(VibesColors.textPrimary)
                .padding(.horizontal)
            RecentlyPlayedCarousel(songs: songs)
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
            HStack(spacing: 10) {
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
                .background(isSelected ? VibesColors.accent : VibesColors.elevated)
                .foregroundColor(isSelected ? .black : VibesColors.textPrimary)
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
            HStack(spacing: 12) {
                if let thumbnail = section.thumbnail {
                    VibesArtwork(url: thumbnail, size: 40, radius: 8)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(VibesColors.textPrimary)

                    if let label = section.label {
                        Text(label)
                            .font(.caption)
                            .foregroundColor(VibesColors.textSecondary)
                    }
                }

                Spacer()

                if section.browseId != nil {
                    Image(systemName: "chevron.right")
                        .foregroundColor(VibesColors.textSecondary)
                        .font(.caption)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
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
                Text("Géneros y estados de ánimo")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(VibesColors.textPrimary)

                Spacer()

                NavigationLink(destination: MoodAndGenresView()) {
                    Text("Ver todo")
                        .font(.subheadline)
                        .foregroundColor(VibesColors.accent)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
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
                .foregroundColor(VibesColors.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(VibesColors.elevated)
                .cornerRadius(10)
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    Rectangle()
                        .fill(VibesColors.elevated)
                        .frame(width: 150, height: 24)
                        .cornerRadius(4)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(0..<4, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 8) {
                                    Rectangle()
                                        .fill(VibesColors.elevated)
                                        .frame(width: 150, height: 150)
                                        .cornerRadius(14)

                                    Rectangle()
                                        .fill(VibesColors.elevated)
                                        .frame(width: 110, height: 14)
                                        .cornerRadius(4)

                                    Rectangle()
                                        .fill(VibesColors.elevated)
                                        .frame(width: 75, height: 12)
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
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(VibesColors.textTertiary)

            Text(message)
                .foregroundColor(VibesColors.textSecondary)

            Button("Reintentar") {
                onRetry()
            }
            .buttonStyle(.borderedProminent)
            .tint(VibesColors.accent)
            .foregroundColor(.black)
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
            VibesPlaylistCard(
                title: song.title,
                subtitle: song.artistsText ?? "",
                artworkUrl: song.thumbnailUrl,
                width: 150
            )
        }
        .buttonStyle(.plain)
        .songContextMenu(song: song)
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
                await libraryManager.saveSong(ytSong)
                if let song = await libraryManager.getSong(id: ytSong.id) {
                    await queueManager.setQueue([song])
                }
            }
        }) {
            VibesPlaylistCard(
                title: ytSong.title,
                subtitle: ytSong.artists,
                artworkUrl: ytSong.thumbnailUrl,
                width: 150
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Album Card

struct AlbumCard: View {
    let album: YTAlbum

    var body: some View {
        VibesPlaylistCard(
            title: album.title,
            subtitle: album.artists,
            artworkUrl: album.thumbnailUrl,
            width: 150
        )
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
                    .fill(VibesColors.elevated)
            }
            .frame(width: 150, height: 150)

            Text(artist.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(VibesColors.textPrimary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            Text("Artista")
                .font(.caption)
                .foregroundColor(VibesColors.textSecondary)
                .frame(width: 150, alignment: .leading)
        }
        .frame(width: 150)
    }
}

// MARK: - Playlist Card

struct PlaylistCard: View {
    let ytPlaylist: YTPlaylist

    var body: some View {
        VibesPlaylistCard(
            title: ytPlaylist.name,
            subtitle: ytPlaylist.author ?? "",
            artworkUrl: ytPlaylist.thumbnailUrl,
            width: 150
        )
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
                        color: VibesColors.accent
                    )
                }

                NavigationLink(destination: NewReleasesView()) {
                    QuickAccessButton(
                        icon: "sparkles",
                        title: "New Releases",
                        color: VibesColors.accent
                    )
                }

                NavigationLink(destination: HistoryView()) {
                    QuickAccessButton(
                        icon: "clock.arrow.circlepath",
                        title: "History",
                        color: VibesColors.accent
                    )
                }

                NavigationLink(destination: MoodAndGenresView()) {
                    QuickAccessButton(
                        icon: "theatermasks",
                        title: "Moods",
                        color: VibesColors.accent
                    )
                }

                NavigationLink(destination: StatsView()) {
                    QuickAccessButton(
                        icon: "chart.bar.fill",
                        title: "Stats",
                        color: VibesColors.accent
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
                .foregroundColor(.black)
                .frame(width: 56, height: 56)
                .background(color)
                .cornerRadius(14)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(VibesColors.textPrimary)
        }
        .frame(width: 80)
    }
}
