import Foundation
import SwiftData

@MainActor
class LyricsManager: ObservableObject {
    static let shared = LyricsManager()

    @Published var currentLyrics: Lyrics?
    @Published var currentLineIndex: Int = 0

    private var modelContext: ModelContext?
    private let providers: [LyricsProvider]
    private var lruCache: [String: Lyrics] = [:]  // In-memory LRU cache
    private var cacheOrder: [String] = []
    private let maxCacheSize = 3  // Keep last 3 songs in memory

    private init() {
        // Provider fallback chain: LrcLib -> KuGou -> YouTube Subtitle -> YouTube Native
        self.providers = [
            LrcLibProvider(),
            KuGouProvider(),
            YouTubeSubtitleProvider(),
            YouTubeNativeProvider()
        ]
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    /// Fetch lyrics for a song (with caching and provider fallback)
    func fetchLyrics(for song: Song) async {
        currentLyrics = nil
        currentLineIndex = 0

        // Check in-memory cache first
        if let cached = lruCache[song.id] {
            dlog("🎵 [Lyrics] Using in-memory cache for \(song.title)")
            currentLyrics = cached
            updateCacheOrder(songId: song.id)
            return
        }

        // Check database cache
        if let context = modelContext {
            let songId = song.id
            let descriptor = FetchDescriptor<Lyrics>(
                predicate: #Predicate { $0.songId == songId }
            )
            if let dbLyrics = try? context.fetch(descriptor).first {
                dlog("🎵 [Lyrics] Using database cache for \(song.title) (source: \(dbLyrics.source))")
                currentLyrics = dbLyrics
                addToMemoryCache(songId: song.id, lyrics: dbLyrics)
                return
            }
        }

        // Fetch from providers (fallback chain)
        dlog("🎵 [Lyrics] Fetching lyrics for \(song.title) from providers...")
        for provider in providers {
            do {
                if let lyrics = try await provider.fetchLyrics(song: song) {
                    dlog("✅ [Lyrics] Found lyrics from \(provider.name)")
                    currentLyrics = lyrics

                    // Save to database
                    if let context = modelContext {
                        context.insert(lyrics)
                        try? context.save()
                    }

                    // Add to memory cache
                    addToMemoryCache(songId: song.id, lyrics: lyrics)
                    return
                }
            } catch {
                dlog("⚠️ [Lyrics] Failed to fetch from \(provider.name): \(error)")
            }
        }

        dlog("❌ [Lyrics] No lyrics found for \(song.title)")
    }

    /// Update current line index based on playback time
    func updateCurrentLine(currentTime: TimeInterval) {
        guard let lyrics = currentLyrics, lyrics.synced else { return }

        // Find the line that should be displayed at current time
        // Use binary search for performance
        var left = 0
        var right = lyrics.lines.count - 1
        var result = 0

        while left <= right {
            let mid = (left + right) / 2
            guard let timestamp = lyrics.lines[mid].timestamp else { break }

            if timestamp <= currentTime {
                result = mid
                left = mid + 1
            } else {
                right = mid - 1
            }
        }

        if currentLineIndex != result {
            currentLineIndex = result
        }
    }

    /// Clear all cached lyrics
    func clearCache() {
        lruCache.removeAll()
        cacheOrder.removeAll()

        // Clear database
        if let context = modelContext {
            do {
                try context.delete(model: Lyrics.self)
                dlog("✅ [Lyrics] Cache cleared")
            } catch {
                dlog("❌ [Lyrics] Failed to clear cache: \(error)")
            }
        }
    }

    // MARK: - LRU Cache Management

    private func addToMemoryCache(songId: String, lyrics: Lyrics) {
        lruCache[songId] = lyrics
        updateCacheOrder(songId: songId)

        // Enforce max cache size
        if cacheOrder.count > maxCacheSize {
            let oldest = cacheOrder.removeFirst()
            lruCache.removeValue(forKey: oldest)
        }
    }

    private func updateCacheOrder(songId: String) {
        cacheOrder.removeAll { $0 == songId }
        cacheOrder.append(songId)
    }
}
