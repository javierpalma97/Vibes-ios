import Foundation

/// Protocol for lyrics providers
protocol LyricsProvider {
    var name: String { get }
    func fetchLyrics(song: Song) async throws -> Lyrics?
}

// MARK: - LrcLib Provider

/// Primary lyrics provider using LrcLib API (https://lrclib.net/)
/// Best for English, Japanese, Korean songs with high accuracy
class LrcLibProvider: LyricsProvider {
    let name = "LrcLib"
    private let baseURL = "https://lrclib.net/api"

    func fetchLyrics(song: Song) async throws -> Lyrics? {
        // Search by track name and artist
        let trackName = song.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? song.title
        let artistName = (song.artistsText ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let searchURL = "\(baseURL)/search?track_name=\(trackName)&artist_name=\(artistName)"

        guard let url = URL(string: searchURL) else {
            print("❌ [LrcLib] Invalid URL: \(searchURL)")
            return nil
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let results = try JSONDecoder().decode([LrcLibSearchResult].self, from: data)

        // Find best match by duration (within 5 seconds)
        guard let songDuration = song.duration else {
            // No duration info, use first result
            guard let first = results.first else { return nil }
            return parseLrcLibResult(first, songId: song.id)
        }

        let bestMatch = results.min(by: { result1, result2 in
            let diff1 = abs(result1.duration - songDuration)
            let diff2 = abs(result2.duration - songDuration)
            return diff1 < diff2
        })

        guard let match = bestMatch, abs(match.duration - songDuration) < 5.0 else {
            print("⚠️ [LrcLib] No match found within duration threshold")
            return nil
        }

        return parseLrcLibResult(match, songId: song.id)
    }

    private func parseLrcLibResult(_ result: LrcLibSearchResult, songId: String) -> Lyrics? {
        // Prefer synced lyrics, fallback to plain
        if let syncedLyrics = result.syncedLyrics, !syncedLyrics.isEmpty {
            let lines = parseLRC(syncedLyrics)
            return Lyrics(songId: songId, lines: lines, synced: true, source: name)
        } else if let plainLyrics = result.plainLyrics, !plainLyrics.isEmpty {
            let lines = plainLyrics.split(separator: "\n").map { LyricsLine(text: String($0)) }
            return Lyrics(songId: songId, lines: lines, synced: false, source: name)
        }
        return nil
    }

    private func parseLRC(_ lrc: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []

        for line in lrc.split(separator: "\n") {
            let lineStr = String(line)

            // Match [mm:ss.xx] or [mm:ss]
            let pattern = #"\[(\d+):(\d+)\.?(\d+)?\](.+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: lineStr, range: NSRange(lineStr.startIndex..., in: lineStr)) else {
                continue
            }

            guard let minutesRange = Range(match.range(at: 1), in: lineStr),
                  let secondsRange = Range(match.range(at: 2), in: lineStr),
                  let textRange = Range(match.range(at: 4), in: lineStr) else {
                continue
            }

            let minutes = Double(lineStr[minutesRange]) ?? 0
            let seconds = Double(lineStr[secondsRange]) ?? 0
            let centiseconds = match.range(at: 3).location != NSNotFound ?
                Double(lineStr[Range(match.range(at: 3), in: lineStr)!]) ?? 0 : 0

            let timestamp = minutes * 60 + seconds + centiseconds / 100
            let text = String(lineStr[textRange])

            lines.append(LyricsLine(timestamp: timestamp, text: text))
        }

        return lines.sorted { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
    }
}

struct LrcLibSearchResult: Codable {
    let trackName: String
    let artistName: String
    let duration: TimeInterval
    let syncedLyrics: String?
    let plainLyrics: String?
}

// MARK: - KuGou Provider

/// Fallback provider using KuGou API (Chinese service)
/// Good for Asian music and songs not in LrcLib
class KuGouProvider: LyricsProvider {
    let name = "KuGou"
    private let searchURL = "https://lyrics.kugou.com/search"
    private let lyricsURL = "https://lyrics.kugou.com/download"

    func fetchLyrics(song: Song) async throws -> Lyrics? {
        // KuGou API requires specific parameters
        // Implementation simplified - full API requires keyword search + accesskey
        print("⚠️ [KuGou] Provider not fully implemented (requires API key)")
        return nil
    }
}

// MARK: - YouTube Subtitle Provider

/// Fetches lyrics from YouTube auto-generated or manual subtitles
class YouTubeSubtitleProvider: LyricsProvider {
    let name = "YouTube Subtitle"

    func fetchLyrics(song: Song) async throws -> Lyrics? {
        // Fetch subtitle tracks from YouTube video
        // This requires parsing the player response for caption tracks
        print("⚠️ [YouTube Subtitle] Provider not fully implemented")
        return nil
    }
}

// MARK: - YouTube Native Provider

/// Fetches lyrics from YouTube Music's native lyrics endpoint (InnerTube)
class YouTubeNativeProvider: LyricsProvider {
    let name = "YouTube Native"
    private let ytMusic = YouTubeMusic.shared

    func fetchLyrics(song: Song) async throws -> Lyrics? {
        // YouTube Music has a browse endpoint for lyrics: browse?browseId=lyrics/{videoId}
        // This would require adding a new method to YouTubeMusic client
        print("⚠️ [YouTube Native] Provider not fully implemented (requires InnerTube browse endpoint)")
        return nil
    }
}
