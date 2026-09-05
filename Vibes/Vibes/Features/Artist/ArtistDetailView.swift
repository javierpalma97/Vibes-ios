import SwiftUI

struct ArtistDetailView: View {
    let artist: YTArtist

    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playerManager: PlayerManager

    @State private var artistPage: ArtistPage?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let ytMusic = YouTubeMusic.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ArtistHeader(
                    artist: artistPage?.artist ?? artist,
                    description: artistPage?.description,
                    onShuffle: shufflePlay,
                    onRadio: startRadio
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
                                await loadArtist()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VibesColors.accent)
                        .foregroundColor(.black)
                    }
                    .padding(.top, 40)
                } else if let sections = artistPage?.sections {
                    ForEach(sections.indices, id: \.self) { index in
                        ArtistSectionView(section: sections[index])
                    }
                }

                Spacer(minLength: 140)
            }
        }
        .vibesBackground()
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadArtist()
        }
    }

    private func loadArtist() async {
        isLoading = true
        errorMessage = nil

        do {
            let page = try await ytMusic.getArtist(browseId: artist.id)
            await MainActor.run {
                artistPage = page
            }
        } catch {
            dlog("❌ [Artist] Error loading artist: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load artist"
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    private func shufflePlay() {
        Task {
            var allSongs: [YTSong] = []

            if let sections = artistPage?.sections {
                for section in sections {
                    for item in section.items {
                        if case .song(let song) = item {
                            allSongs.append(song)
                        }
                    }
                }
            }

            var librarySongs: [Song] = []
            for ytSong in allSongs {
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

    private func startRadio() {
        Task {
            var allSongs: [YTSong] = []

            if let sections = artistPage?.sections {
                for section in sections {
                    for item in section.items {
                        if case .song(let song) = item {
                            allSongs.append(song)
                        }
                    }
                }
            }

            var librarySongs: [Song] = []
            for ytSong in allSongs {
                await libraryManager.saveSong(ytSong)
                if let song = await libraryManager.getSong(id: ytSong.id) {
                    librarySongs.append(song)
                }
            }

            if !librarySongs.isEmpty {
                await queueManager.setQueue(librarySongs, startIndex: 0, enableRadio: true)
            }
        }
    }
}

// MARK: - Artist Header

struct ArtistHeader: View {
    let artist: YTArtist
    let description: String?
    let onShuffle: () -> Void
    let onRadio: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            AsyncImage(url: URL(string: artist.thumbnailUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(VibesColors.elevated)
            }
            .frame(width: 180, height: 180)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

            Text(artist.name)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(VibesColors.textPrimary)

            if let description = description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(VibesColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button(action: onShuffle) {
                    HStack {
                        Image(systemName: "shuffle")
                        Text("Aleatorio")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(VibesColors.accent)
                    .foregroundColor(.black)
                    .cornerRadius(12)
                }

                Button(action: onRadio) {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right")
                        Text("Radio")
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
        }
        .padding()
    }
}

// MARK: - Artist Section View

struct ArtistSectionView: View {
    let section: ArtistSection
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(section.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(VibesColors.textPrimary)

                Spacer()

                if section.browseId != nil {
                    Text("Ver todo")
                        .font(.subheadline)
                        .foregroundColor(VibesColors.accent)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(section.items.indices, id: \.self) { index in
                        ArtistItemView(item: section.items[index])
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Artist Item View

struct ArtistItemView: View {
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

// MARK: - Artist Page Model

struct ArtistPage {
    let artist: YTArtist
    let sections: [ArtistSection]
    let description: String?
}

struct ArtistSection {
    let title: String
    let items: [HomeItem]
    let browseId: String?
}
