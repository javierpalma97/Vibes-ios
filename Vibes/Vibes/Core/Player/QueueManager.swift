import Foundation
import SwiftData

@MainActor
class QueueManager: ObservableObject {
    static let shared = QueueManager()

    @Published var queue: [Song] = []
    @Published var originalQueue: [Song] = []
    @Published var currentIndex: Int = -1

    private let playerManager = PlayerManager.shared
    private let libraryManager = LibraryManager.shared
    private let ytMusic = YouTubeMusic.shared

    // Radio mode - for infinite playback
    private var isRadioMode: Bool = false
    private var radioVideoId: String?
    private var radioContinuation: String?
    private var isFetchingMore: Bool = false

    private init() {
        loadPersistedQueue()
    }

    // MARK: - Queue Management

    func setQueue(_ songs: [Song], startIndex: Int = 0, enableRadio: Bool = true) {
        self.originalQueue = songs
        self.queue = playerManager.isShuffleEnabled ? songs.shuffled() : songs
        self.currentIndex = startIndex

        // Enable radio mode for continuous playback if queue is small
        if enableRadio && songs.count <= 25 {
            isRadioMode = true
            if startIndex >= 0 && startIndex < songs.count {
                radioVideoId = songs[startIndex].id
            }
            radioContinuation = nil
            // Start fetching more songs in the background
            Task {
                await fetchMoreRadioSongs()
            }
        } else {
            isRadioMode = false
            radioVideoId = nil
            radioContinuation = nil
        }

        persistQueue()

        if startIndex >= 0 && startIndex < queue.count {
            let song = queue[startIndex]
            Task {
                await playerManager.playSong(song)
                libraryManager.incrementPlayCount(song: song, playTime: 0)
            }
        }
    }

    func addToQueue(_ song: Song) {
        queue.append(song)
        originalQueue.append(song)
        persistQueue()
    }

    func addToQueue(_ songs: [Song]) {
        queue.append(contentsOf: songs)
        originalQueue.append(contentsOf: songs)
        persistQueue()
    }

    func insertNext(_ song: Song) {
        let nextIndex = currentIndex + 1
        if nextIndex <= queue.count {
            queue.insert(song, at: nextIndex)
            originalQueue.insert(song, at: nextIndex)
        } else {
            queue.append(song)
            originalQueue.append(song)
        }
        persistQueue()
    }

    func removeFromQueue(at index: Int) {
        guard index >= 0 && index < queue.count else { return }

        let song = queue[index]
        queue.remove(at: index)

        if let originalIndex = originalQueue.firstIndex(where: { $0.id == song.id }) {
            originalQueue.remove(at: originalIndex)
        }

        if index < currentIndex {
            currentIndex -= 1
        }

        persistQueue()
    }

    func moveItem(from source: Int, to destination: Int) {
        guard source >= 0 && source < queue.count &&
              destination >= 0 && destination < queue.count else {
            return
        }

        let song = queue.remove(at: source)
        queue.insert(song, at: destination)

        if source == currentIndex {
            currentIndex = destination
        } else if source < currentIndex && destination >= currentIndex {
            currentIndex -= 1
        } else if source > currentIndex && destination <= currentIndex {
            currentIndex += 1
        }

        persistQueue()
    }

    func clearQueue() {
        queue.removeAll()
        originalQueue.removeAll()
        currentIndex = -1
        persistQueue()
    }

    // MARK: - Playback Navigation

    func playNext() async {
        guard !queue.isEmpty else { return }

        // Fetch more songs if in radio mode and approaching end of queue
        if isRadioMode && currentIndex >= queue.count - 5 {
            await fetchMoreRadioSongs()
        }

        if currentIndex < queue.count - 1 {
            currentIndex += 1
            let song = queue[currentIndex]
            await playerManager.playSong(song)
            libraryManager.incrementPlayCount(song: song, playTime: 0)
            persistQueue()
        } else if playerManager.repeatMode == .all {
            currentIndex = 0
            let song = queue[currentIndex]
            await playerManager.playSong(song)
            libraryManager.incrementPlayCount(song: song, playTime: 0)
            persistQueue()
        }
    }

    func playPrevious() async {
        guard !queue.isEmpty else { return }

        // If more than 3 seconds into the song, restart it
        if playerManager.currentTime > 3.0 {
            playerManager.seek(to: 0)
            return
        }

        if currentIndex > 0 {
            currentIndex -= 1
            let song = queue[currentIndex]
            await playerManager.playSong(song)
            libraryManager.incrementPlayCount(song: song, playTime: 0)
            persistQueue()
        } else if playerManager.repeatMode == .all {
            currentIndex = queue.count - 1
            let song = queue[currentIndex]
            await playerManager.playSong(song)
            libraryManager.incrementPlayCount(song: song, playTime: 0)
            persistQueue()
        }
    }

    func playAt(index: Int) async {
        guard index >= 0 && index < queue.count else { return }
        currentIndex = index
        let song = queue[index]
        await playerManager.playSong(song)
        libraryManager.incrementPlayCount(song: song, playTime: 0)
        persistQueue()
    }

    // MARK: - Radio Mode

    private func fetchMoreRadioSongs() async {
        guard isRadioMode,
              let videoId = radioVideoId,
              !isFetchingMore else { return }

        isFetchingMore = true

        do {
            let (ytSongs, continuation) = try await ytMusic.getRadioQueue(
                videoId: videoId,
                continuation: radioContinuation
            )

            // Save songs to database and convert to Song objects
            var newSongs: [Song] = []
            for ytSong in ytSongs {
                await libraryManager.saveSong(ytSong)
                if let song = await libraryManager.getSong(id: ytSong.id) {
                    newSongs.append(song)
                }
            }

            // Add to queue
            if !newSongs.isEmpty {
                queue.append(contentsOf: newSongs)
                originalQueue.append(contentsOf: newSongs)
                radioContinuation = continuation
                persistQueue()
            }
        } catch {
            print("❌ [Queue] Failed to fetch more radio songs: \(error)")
        }

        isFetchingMore = false
    }

    // MARK: - Shuffle

    func toggleShuffle() {
        playerManager.isShuffleEnabled.toggle()

        if playerManager.isShuffleEnabled {
            // Shuffle the queue, keeping current song at the current position
            var shuffled = originalQueue
            if currentIndex >= 0 && currentIndex < shuffled.count {
                let currentSong = shuffled[currentIndex]
                shuffled.remove(at: currentIndex)
                shuffled.shuffle()
                shuffled.insert(currentSong, at: currentIndex)
            } else {
                shuffled.shuffle()
            }
            queue = shuffled
        } else {
            // Restore original order
            if currentIndex >= 0 && currentIndex < queue.count {
                let currentSong = queue[currentIndex]
                queue = originalQueue
                if let newIndex = queue.firstIndex(where: { $0.id == currentSong.id }) {
                    currentIndex = newIndex
                }
            } else {
                queue = originalQueue
            }
        }

        persistQueue()
    }

    // MARK: - Persistence

    private func persistQueue() {
        let queueData = QueueData(
            songIds: queue.map { $0.id },
            currentIndex: currentIndex,
            isShuffled: playerManager.isShuffleEnabled
        )

        if let encoded = try? JSONEncoder().encode(queueData) {
            UserDefaults.standard.set(encoded, forKey: "queueData")
        }
    }

    private func loadPersistedQueue() {
        guard let data = UserDefaults.standard.data(forKey: "queueData"),
              let queueData = try? JSONDecoder().decode(QueueData.self, from: data) else {
            return
        }

        // Load actual Song objects from database
        Task {
            var loadedSongs: [Song] = []
            for songId in queueData.songIds {
                if let song = await libraryManager.getSong(id: songId) {
                    loadedSongs.append(song)
                }
            }

            // Only restore queue if we found some songs
            if !loadedSongs.isEmpty {
                self.queue = loadedSongs
                self.originalQueue = loadedSongs

                // Restore index, but clamp to valid range
                self.currentIndex = min(max(0, queueData.currentIndex), loadedSongs.count - 1)

                print("📋 [Queue] Restored queue with \(loadedSongs.count) songs, index: \(self.currentIndex)")
            }
        }
    }

    // MARK: - Current Song

    var currentSong: Song? {
        guard currentIndex >= 0 && currentIndex < queue.count else {
            return nil
        }
        return queue[currentIndex]
    }

    var hasNext: Bool {
        return currentIndex < queue.count - 1 || playerManager.repeatMode == .all
    }

    var hasPrevious: Bool {
        return currentIndex > 0 || playerManager.repeatMode == .all
    }
}

// MARK: - Queue Data Model

struct QueueData: Codable {
    let songIds: [String]
    let currentIndex: Int
    let isShuffled: Bool
}
