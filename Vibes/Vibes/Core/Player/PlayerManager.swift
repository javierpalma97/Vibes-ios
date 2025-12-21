import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit

enum RepeatMode: String, Codable {
    case off
    case one
    case all
}

enum PlayerState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case error(Error)

    static func == (lhs: PlayerState, rhs: PlayerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.playing, .playing), (.paused, .paused), (.buffering, .buffering):
            return true
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}

@MainActor
class PlayerManager: NSObject, ObservableObject {
    static let shared = PlayerManager()

    // MARK: - Published Properties

    @Published var currentSong: Song?
    @Published var playerState: PlayerState = .idle
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isShuffleEnabled: Bool = false
    @Published var shouldShowFullPlayer: Bool = false

    // MARK: - Private Properties

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var itemEndObserver: NSObjectProtocol?

    private let ytMusic = YouTubeMusic.shared
    private var cancellables = Set<AnyCancellable>()

    private var streamUrlCache: [String: (url: String, expiry: TimeInterval)] = [:]
    private var resourceLoader: CustomResourceLoader?

    // Skip silence support (Note: Full implementation requires AVAudioEngine for buffer access)
    nonisolated(unsafe) private var silenceCheckTimer: Timer?
    private var lastVolumeCheckTime: TimeInterval = 0

    private override init() {
        super.init()
        setupPlayer()
        setupNotifications()
        setupInterruptionHandling()
    }

    // MARK: - Setup

    private func setupPlayer() {
        // Configure audio session for playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            print("🎵 [Player] Audio session configured for playback")
        } catch {
            print("❌ [Player] Failed to configure audio session: \(error)")
        }

        player = AVPlayer()
        player?.automaticallyWaitsToMinimizeStalling = true

        // Add time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds

            // Update lyrics current line
            Task { @MainActor in
                LyricsManager.shared.updateCurrentLine(currentTime: time.seconds)
            }
        }

        // Observe player rate changes
        player?.publisher(for: \.rate)
            .sink { [weak self] rate in
                guard let self = self else { return }
                Task { @MainActor in
                    self.isPlaying = rate > 0
                }
            }
            .store(in: &cancellables)
    }

    private func setupNotifications() {
        // Observe when item finishes playing
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleItemEnd()
            }
        }
    }

    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            pause()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    play()
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Skip Silence

    private func startSilenceMonitoring() {
        stopSilenceMonitoring() // Clear any existing timer

        silenceCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndSkipSilence()
            }
        }
    }

    nonisolated private func stopSilenceMonitoring() {
        silenceCheckTimer?.invalidate()
        silenceCheckTimer = nil
    }

    private func checkAndSkipSilence() {
        // NOTE: True silence detection requires AVAudioEngine for PCM buffer access.
        // This is a simplified heuristic-based approach using AVPlayer.
        // For full silence detection with RMS analysis, migration to AVAudioEngine is needed.

        guard let player = player,
              let currentItem = player.currentItem,
              isPlaying,
              currentTime > 0 else {
            return
        }

        // Heuristic: Check if we're in a potentially silent section based on playback behavior
        // This is a placeholder for future AVAudioEngine implementation
        // Real implementation would analyze audio buffers using Accelerate framework

        // For now, we detect buffering/stalling which might indicate issues
        // Full silence detection would require:
        // 1. AVAudioEngine with tap on player output
        // 2. RMS calculation using vDSP_rmsqv from Accelerate
        // 3. dB conversion and threshold checking (< -50dB)

        // Skip implementation deferred until AVAudioEngine migration
    }

    // MARK: - Playback Control

    func playSong(_ song: Song) async {
        print("🎵 [Player] Starting to play: \(song.title)")
        self.currentSong = song
        self.playerState = .loading
        self.duration = 0  // Reset duration before loading new song
        self.currentTime = 0
        self.shouldShowFullPlayer = true  // Show full player when song starts

        // Fetch lyrics in background
        Task {
            await LyricsManager.shared.fetchLyrics(for: song)
        }

        // Update theme colors based on artwork
        Task {
            await ThemeManager.shared.updateTheme(from: song.thumbnailUrl)
        }

        do {
            let url: URL
            let newPlayerItem: AVPlayerItem
            var youtubeDuration: TimeInterval?
            var youtubeLoudness: Double?

            // Check if song is downloaded locally
            let downloadManager = DownloadManager.shared
            if downloadManager.isDownloaded(song.id) {
                print("🎵 [Player] Playing DOWNLOADED file for \(song.title)")
                let localURL = downloadManager.localFileURL(for: song.id)
                url = localURL
                newPlayerItem = AVPlayerItem(url: url)

                // Still fetch YouTube API duration for correct metadata (even for downloaded files)
                // This is a lightweight call and fixes doubled durations in downloaded files
                do {
                    let (_, duration, _, loudness) = try await getStreamUrl(for: song.id)
                    youtubeDuration = duration
                    youtubeLoudness = loudness
                    print("🎵 [Player] Fetched YouTube API duration for downloaded file: \(duration ?? -1)s, loudness: \(loudness ?? -14)dB")
                } catch {
                    print("⚠️ [Player] Could not fetch YouTube duration for downloaded file: \(error)")
                }
            } else {
                print("🎵 [Player] Playing STREAMED file for \(song.title)")
                // Get stream URL from network
                let (streamUrl, duration, _, loudness) = try await getStreamUrl(for: song.id)
                youtubeDuration = duration
                youtubeLoudness = loudness
                print("🎵 [Player] Got YouTube API duration: \(duration ?? -1)s, loudness: \(loudness ?? -14)dB")

                guard let remoteURL = URL(string: streamUrl) else {
                    self.playerState = .error(PlayerError.invalidUrl)
                    return
                }
                url = remoteURL

                // Use URL directly - simple and clean like Android
                newPlayerItem = AVPlayerItem(url: url)
            }

            // Remove old observers
            statusObserver?.invalidate()

            // Observe status
            statusObserver = newPlayerItem.observe(\.status, options: [.new, .old]) { [weak self] item, _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.handleStatusChange(item: item)
                }
            }

            // Replace current item
            self.playerItem = newPlayerItem
            player?.replaceCurrentItem(with: newPlayerItem)

            // Update duration - prioritize YouTube API duration over stored duration
            if let ytDuration = youtubeDuration {
                self.duration = ytDuration
                print("🎵 [Player] Set duration from YouTube API: \(ytDuration)s for \(song.title)")
            } else if let duration = song.duration {
                self.duration = duration
                print("🎵 [Player] Set duration from song.duration: \(duration)s for \(song.title)")
            }

            // Update now playing info
            updateNowPlayingInfo()

            // Start playback
            play()

            // Apply audio normalization if enabled
            let normalizeAudio = UserDefaults.standard.bool(forKey: "normalizeAudio")
            if normalizeAudio, let loudnessDb = youtubeLoudness {
                // Target: -14 LUFS (Spotify standard)
                let targetLoudness = -14.0
                let gainAdjustment = targetLoudness - loudnessDb

                // Convert dB to linear gain: gain = 10^(dB/20)
                let linearGain = pow(10.0, gainAdjustment / 20.0)

                // Clamp gain to prevent distortion (0.5x - 2.0x)
                let clampedGain = max(0.5, min(2.0, linearGain))

                player?.volume = Float(clampedGain)
                print("🔊 [Player] Applied normalization: \(loudnessDb)dB -> \(targetLoudness)dB (gain: \(clampedGain)x)")
            } else {
                player?.volume = 1.0
                if normalizeAudio {
                    print("⚠️ [Player] Normalization enabled but no loudness data available")
                }
            }

        } catch {
            print("❌ [Player] Error playing song: \(error)")

            // If we get a 404, the videoId might be invalid - delete the song from DB so it can be re-fetched
            if case InnerTubeError.httpError(let statusCode) = error, statusCode == 404 {
                print("⚠️ [Player] 404 error - deleting song from DB to force re-fetch")
                await LibraryManager.shared.deleteSong(song)
            }

            self.playerState = .error(error)
        }
    }

    func play() {
        // Apply playback speed from settings
        let speed = UserDefaults.standard.double(forKey: "playbackSpeed")
        let rate = Float(speed == 0 ? 1.0 : speed)
        player?.rate = rate

        playerState = .playing
        updateNowPlayingInfo()

        // Start skip silence monitoring if enabled
        let skipSilence = UserDefaults.standard.bool(forKey: "skipSilence")
        if skipSilence {
            startSilenceMonitoring()
        }
    }

    func pause() {
        player?.pause()
        playerState = .paused
        updateNowPlayingInfo()

        // Stop silence monitoring when paused
        stopSilenceMonitoring()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateNowPlayingInfo()
            }
        }
    }

    func setPlaybackSpeed(_ speed: Double) {
        guard let player = player else { return }
        let rate = Float(speed)
        player.rate = isPlaying ? rate : 0 // Only apply if currently playing
        print("🎵 [Player] Playback speed set to \(speed)x")
        updateNowPlayingInfo()
    }

    func playNext() {
        Task {
            await QueueManager.shared.playNext()
        }
    }

    func playPrevious() {
        Task {
            await QueueManager.shared.playPrevious()
        }
    }

    // MARK: - Stream URL Management

    private func getStreamUrl(for videoId: String) async throws -> (url: String, duration: TimeInterval?, clientType: InnerTubeClientType, loudnessDb: Double?) {
        // ALWAYS fetch fresh data to get correct duration (YouTube API is source of truth)
        // Don't use cache because cached URLs don't include duration, leading to doubled durations from asset
        print("🎵 [Player] Fetching fresh stream URL for \(videoId)")

        // Fetch new URL, duration, and client type
        let (url, expiry, duration, clientType, loudnessDb) = try await ytMusic.getStreamUrl(videoId: videoId)

        // Cache it
        if let expiry = expiry {
            streamUrlCache[videoId] = (url, expiry)
        }

        return (url: url, duration: duration, clientType: clientType, loudnessDb: loudnessDb)
    }

    // MARK: - Status Handling

    private func handleStatusChange(item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            // Use YouTube API duration as source of truth (asset duration is often doubled)
            let assetDuration = item.asset.duration.seconds
            print("🎵 [Player] Asset ready - YouTube API duration: \(self.duration)s, asset duration: \(assetDuration)s")

            // If we have YouTube API duration, KEEP it and ignore asset
            if self.duration > 0 {
                // We have YouTube API duration - this is correct, don't change it
                if abs(self.duration - assetDuration) > 2.0 {
                    print("⚠️ [Player] Asset duration (\(assetDuration)s) differs from YouTube API (\(self.duration)s). Using YouTube API (correct).")
                }
                // Keep self.duration from YouTube API, update song database
                if let song = self.currentSong {
                    let minutes = Int(self.duration) / 60
                    let seconds = Int(self.duration) % 60
                    song.durationText = String(format: "%d:%02d", minutes, seconds)
                }
            } else if assetDuration.isFinite && assetDuration > 0 {
                // No YouTube API duration, fall back to asset (likely downloaded file)
                self.duration = assetDuration
                print("🎵 [Player] Using asset duration (no YouTube API duration available): \(assetDuration)s")

                if let song = self.currentSong {
                    let minutes = Int(assetDuration) / 60
                    let seconds = Int(assetDuration) % 60
                    song.durationText = String(format: "%d:%02d", minutes, seconds)
                }
            }

            if playerState == .loading {
                playerState = .playing
            }
        case .failed:
            if let error = item.error {
                print("❌ [Player] Error: \(error.localizedDescription)")
                playerState = .error(error)
            }
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func statusString(_ status: AVPlayerItem.Status) -> String {
        switch status {
        case .unknown: return "unknown"
        case .readyToPlay: return "readyToPlay"
        case .failed: return "failed"
        @unknown default: return "@unknown"
        }
    }

    private func handleItemEnd() {
        // Track play event (matching Android)
        if let song = currentSong, duration > 0 {
            let playTimeMs = Int64(duration * 1000) // Convert to milliseconds
            LibraryManager.shared.trackPlayEvent(songId: song.id, playTime: playTimeMs)
        }

        switch repeatMode {
        case .one:
            // Replay current song
            seek(to: 0)
            play()
        case .all, .off:
            // Play next song
            playNext()
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()

        if let song = currentSong {
            nowPlayingInfo[MPMediaItemPropertyTitle] = song.title
            nowPlayingInfo[MPMediaItemPropertyArtist] = song.artistsText ?? "Unknown Artist"
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = song.albumName ?? ""
        }

        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime

        // Include actual playback speed
        let speed = UserDefaults.standard.double(forKey: "playbackSpeed")
        let rate = speed == 0 ? 1.0 : speed
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? rate : 0.0

        // Set artwork asynchronously
        if let thumbnailUrl = currentSong?.thumbnailUrl {
            Task {
                if let artwork = await loadArtwork(from: thumbnailUrl) {
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func loadArtwork(from urlString: String) async -> MPMediaItemArtwork? {
        guard let url = URL(string: urlString),
              let data = try? await URLSession.shared.data(from: url).0,
              let image = UIImage(data: data) else {
            return nil
        }

        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    // MARK: - Cleanup

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        statusObserver?.invalidate()
        if let observer = itemEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        stopSilenceMonitoring()
    }
}

enum PlayerError: Error {
    case invalidUrl
    case streamNotAvailable
    case networkError
}
