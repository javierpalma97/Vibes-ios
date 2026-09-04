import CarPlay
import MediaPlayer
import UIKit
import Combine

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    var sessionConfiguration: CPSessionConfiguration?

    private let playerManager = PlayerManager.shared
    private let queueManager = QueueManager.shared
    private let libraryManager = LibraryManager.shared

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Scene Lifecycle

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.delegate = self

        // Set up root template
        Task { @MainActor in
            let rootTemplate = await createRootTemplate()
            interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)
        }

        // Observe player changes
        setupObservers()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        cancellables.removeAll()
    }

    private func setupObservers() {
        // Update now playing when song changes
        playerManager.$currentSong
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)

        playerManager.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)
    }

    // MARK: - Template Creation

    @MainActor
    private func createRootTemplate() async -> CPTabBarTemplate {
        let libraryTab = await createLibraryTemplate()
        libraryTab.tabImage = UIImage(systemName: "music.note.list")

        let browseTab = await createBrowseTemplate()
        browseTab.tabImage = UIImage(systemName: "square.grid.2x2")

        let playlistsTab = await createPlaylistsTemplate()
        playlistsTab.tabImage = UIImage(systemName: "list.bullet")

        let nowPlayingTab = CPNowPlayingTemplate.shared
        nowPlayingTab.tabImage = UIImage(systemName: "play.circle.fill")

        // Configure now playing template buttons
        configureNowPlayingTemplate()

        return CPTabBarTemplate(templates: [libraryTab, browseTab, playlistsTab, nowPlayingTab])
    }

    @MainActor
    private func createBrowseTemplate() async -> CPListTemplate {
        var items: [CPListItem] = []

        // Charts
        let chartsItem = CPListItem(
            text: "Charts",
            detailText: "Trending music",
            image: UIImage(systemName: "chart.line.uptrend.xyaxis")
        )
        chartsItem.handler = { [weak self] _, completion in
            Task { @MainActor in
                await self?.showCharts()
            }
            completion()
        }
        items.append(chartsItem)

        // New Releases
        let newReleasesItem = CPListItem(
            text: "New Releases",
            detailText: "Latest albums",
            image: UIImage(systemName: "sparkles")
        )
        newReleasesItem.handler = { [weak self] _, completion in
            Task { @MainActor in
                await self?.showNewReleases()
            }
            completion()
        }
        items.append(newReleasesItem)

        // Quick Picks (shuffle from recent)
        let quickPicksItem = CPListItem(
            text: "Quick Picks",
            detailText: "Shuffle your favorites",
            image: UIImage(systemName: "shuffle")
        )
        quickPicksItem.handler = { [weak self] _, completion in
            Task { @MainActor in
                await self?.playQuickPicks()
            }
            completion()
        }
        items.append(quickPicksItem)

        return CPListTemplate(title: "Browse", sections: [CPListSection(items: items)])
    }

    @MainActor
    private func showCharts() async {
        let loadingItem = CPListItem(text: "Loading...", detailText: nil)
        let loadingTemplate = CPListTemplate(title: "Charts", sections: [CPListSection(items: [loadingItem])])
        interfaceController?.pushTemplate(loadingTemplate, animated: true, completion: nil)

        do {
            let chartsPage = try await YouTubeMusic.shared.getCharts()

            var sections: [CPListSection] = []

            for section in chartsPage.sections.prefix(3) {
                var items: [CPListItem] = []

                for homeItem in section.items.prefix(10) {
                    if case .song(let song) = homeItem {
                        let item = CPListItem(text: song.title, detailText: song.artists)
                        item.handler = { [weak self] _, completion in
                            Task { @MainActor in
                                await self?.playSongFromYT(song)
                            }
                            completion()
                        }
                        items.append(item)
                    }
                }

                if !items.isEmpty {
                    sections.append(CPListSection(items: items, header: section.title, sectionIndexTitle: nil))
                }
            }

            let chartsTemplate = CPListTemplate(title: "Charts", sections: sections)
            interfaceController?.popTemplate(animated: false, completion: nil)
            interfaceController?.pushTemplate(chartsTemplate, animated: true, completion: nil)

        } catch {
            dlog("❌ [CarPlay] Failed to load charts: \(error)")
            let errorItem = CPListItem(text: "Failed to load", detailText: "Try again later")
            let errorTemplate = CPListTemplate(title: "Charts", sections: [CPListSection(items: [errorItem])])
            interfaceController?.popTemplate(animated: false, completion: nil)
            interfaceController?.pushTemplate(errorTemplate, animated: true, completion: nil)
        }
    }

    @MainActor
    private func showNewReleases() async {
        let loadingItem = CPListItem(text: "Loading...", detailText: nil)
        let loadingTemplate = CPListTemplate(title: "New Releases", sections: [CPListSection(items: [loadingItem])])
        interfaceController?.pushTemplate(loadingTemplate, animated: true, completion: nil)

        do {
            let albums = try await YouTubeMusic.shared.getNewReleases()

            let items = albums.prefix(20).map { album -> CPListItem in
                let item = CPListItem(text: album.title, detailText: album.artists)
                item.handler = { [weak self] _, completion in
                    Task { @MainActor in
                        await self?.playAlbum(album)
                    }
                    completion()
                }
                return item
            }

            let template = CPListTemplate(title: "New Releases", sections: [CPListSection(items: Array(items))])
            interfaceController?.popTemplate(animated: false, completion: nil)
            interfaceController?.pushTemplate(template, animated: true, completion: nil)

        } catch {
            dlog("❌ [CarPlay] Failed to load new releases: \(error)")
        }
    }

    @MainActor
    private func playQuickPicks() async {
        let songs = libraryManager.recentlyPlayed
        if !songs.isEmpty {
            await queueManager.setQueue(songs.shuffled())
        }
    }

    @MainActor
    private func playSongFromYT(_ ytSong: YTSong) async {
        await libraryManager.saveSong(ytSong)
        if let song = await libraryManager.getSong(id: ytSong.id) {
            await queueManager.setQueue([song])
        }
    }

    @MainActor
    private func playAlbum(_ album: YTAlbum) async {
        do {
            let (_, songs) = try await YouTubeMusic.shared.getAlbum(browseId: album.id)
            for song in songs {
                await libraryManager.saveSong(song)
            }

            var librarySongs: [Song] = []
            for song in songs {
                if let librarySong = await libraryManager.getSong(id: song.id) {
                    librarySongs.append(librarySong)
                }
            }

            if !librarySongs.isEmpty {
                await queueManager.setQueue(librarySongs)
            }
        } catch {
            dlog("❌ [CarPlay] Failed to play album: \(error)")
        }
    }

    @MainActor
    private func createLibraryTemplate() async -> CPListTemplate {
        var sections: [CPListSection] = []

        // Liked songs section
        let likedSongs = libraryManager.likedSongs
        if !likedSongs.isEmpty {
            let likedItem = CPListItem(
                text: "Liked Songs",
                detailText: "\(likedSongs.count) songs",
                image: UIImage(systemName: "heart.fill")
            )
            likedItem.handler = { [weak self] _, completion in
                Task { @MainActor in
                    await self?.playLikedSongs()
                }
                completion()
            }
            sections.append(CPListSection(items: [likedItem], header: "Your Music", sectionIndexTitle: nil))
        }

        // Recently played section
        let recentSongs = Array(libraryManager.recentlyPlayed.prefix(15))
        if !recentSongs.isEmpty {
            let items = recentSongs.map { song -> CPListItem in
                let item = CPListItem(
                    text: song.title,
                    detailText: song.artistsText ?? "Unknown Artist"
                )
                item.handler = { [weak self] _, completion in
                    Task { @MainActor in
                        await self?.playSong(song)
                    }
                    completion()
                }
                // Load artwork
                if let thumbnailUrl = song.thumbnailUrl {
                    Task {
                        if let image = await self.loadImage(from: thumbnailUrl) {
                            await MainActor.run {
                                item.setImage(image)
                            }
                        }
                    }
                }
                return item
            }
            sections.append(CPListSection(items: items, header: "Recently Played", sectionIndexTitle: nil))
        }

        // If no content, show empty state
        if sections.isEmpty {
            let emptyItem = CPListItem(
                text: "No music yet",
                detailText: "Play some music in the app to see it here"
            )
            sections.append(CPListSection(items: [emptyItem]))
        }

        return CPListTemplate(title: "Library", sections: sections)
    }

    @MainActor
    private func createPlaylistsTemplate() async -> CPListTemplate {
        let playlists = libraryManager.playlists

        if playlists.isEmpty {
            let emptyItem = CPListItem(
                text: "No playlists",
                detailText: "Create playlists in the app"
            )
            return CPListTemplate(title: "Playlists", sections: [CPListSection(items: [emptyItem])])
        }

        let items = playlists.map { playlist -> CPListItem in
            let item = CPListItem(
                text: playlist.name,
                detailText: "\(playlist.songCount) songs",
                image: UIImage(systemName: "music.note.list")
            )
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    await self?.showPlaylist(playlist)
                }
                completion()
            }
            // Load playlist artwork
            if let thumbnailUrl = playlist.thumbnailUrl {
                Task {
                    if let image = await self.loadImage(from: thumbnailUrl) {
                        await MainActor.run {
                            item.setImage(image)
                        }
                    }
                }
            }
            return item
        }

        return CPListTemplate(title: "Playlists", sections: [CPListSection(items: items)])
    }

    private func configureNowPlayingTemplate() {
        let nowPlayingTemplate = CPNowPlayingTemplate.shared

        // Add shuffle button
        let shuffleButton = CPNowPlayingShuffleButton { [weak self] _ in
            Task { @MainActor in
                self?.queueManager.toggleShuffle()
            }
        }

        // Add repeat button
        let repeatButton = CPNowPlayingRepeatButton { [weak self] _ in
            Task { @MainActor in
                self?.toggleRepeat()
            }
        }

        nowPlayingTemplate.updateNowPlayingButtons([shuffleButton, repeatButton])
    }

    // MARK: - Playback Actions

    @MainActor
    private func playSong(_ song: Song) async {
        await queueManager.setQueue([song])
    }

    @MainActor
    private func playLikedSongs() async {
        let songs = libraryManager.likedSongs
        if !songs.isEmpty {
            await queueManager.setQueue(songs.shuffled())
        }
    }

    @MainActor
    private func showPlaylist(_ playlist: Playlist) async {
        let songs = await libraryManager.getPlaylistSongs(playlist)

        if songs.isEmpty {
            let emptyItem = CPListItem(text: "Empty playlist", detailText: "Add songs in the app")
            let emptyTemplate = CPListTemplate(title: playlist.name, sections: [CPListSection(items: [emptyItem])])
            interfaceController?.pushTemplate(emptyTemplate, animated: true, completion: nil)
            return
        }

        // Play all button
        let playAllItem = CPListItem(
            text: "Play All",
            detailText: "\(songs.count) songs",
            image: UIImage(systemName: "play.fill")
        )
        playAllItem.handler = { [weak self] _, completion in
            Task { @MainActor in
                await self?.queueManager.setQueue(songs)
            }
            completion()
        }

        // Shuffle button
        let shuffleItem = CPListItem(
            text: "Shuffle",
            detailText: "Play in random order",
            image: UIImage(systemName: "shuffle")
        )
        shuffleItem.handler = { [weak self] _, completion in
            Task { @MainActor in
                await self?.queueManager.setQueue(songs.shuffled())
            }
            completion()
        }

        // Song items
        let songItems = songs.enumerated().map { index, song -> CPListItem in
            let item = CPListItem(
                text: song.title,
                detailText: song.artistsText ?? "Unknown Artist"
            )
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    await self?.queueManager.setQueue(songs, startIndex: index)
                }
                completion()
            }
            return item
        }

        let sections = [
            CPListSection(items: [playAllItem, shuffleItem], header: "Actions", sectionIndexTitle: nil),
            CPListSection(items: songItems, header: "Songs", sectionIndexTitle: nil)
        ]

        let playlistTemplate = CPListTemplate(title: playlist.name, sections: sections)
        interfaceController?.pushTemplate(playlistTemplate, animated: true, completion: nil)
    }

    private func toggleRepeat() {
        switch playerManager.repeatMode {
        case .off:
            playerManager.repeatMode = .all
        case .all:
            playerManager.repeatMode = .one
        case .one:
            playerManager.repeatMode = .off
        }
    }

    // MARK: - Now Playing

    func updateNowPlayingInfo() {
        guard let currentSong = playerManager.currentSong else { return }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: currentSong.title,
            MPMediaItemPropertyArtist: currentSong.artistsText ?? "Unknown Artist",
            MPMediaItemPropertyPlaybackDuration: playerManager.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: playerManager.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: playerManager.isPlaying ? 1.0 : 0.0
        ]

        if let albumName = currentSong.albumName {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = albumName
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

        // Load artwork asynchronously
        if let thumbnailUrl = currentSong.thumbnailUrl {
            Task {
                if let image = await loadImage(from: thumbnailUrl) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    await MainActor.run {
                        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        info[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

// MARK: - CPInterfaceControllerDelegate

extension CarPlaySceneDelegate: CPInterfaceControllerDelegate {
    func templateWillAppear(_ aTemplate: CPTemplate, animated: Bool) {
        // Refresh content when template appears
    }

    func templateDidAppear(_ aTemplate: CPTemplate, animated: Bool) {
        if aTemplate is CPNowPlayingTemplate {
            updateNowPlayingInfo()
        }
    }

    func templateWillDisappear(_ aTemplate: CPTemplate, animated: Bool) {
    }

    func templateDidDisappear(_ aTemplate: CPTemplate, animated: Bool) {
    }
}
