import Foundation

// Simplified DTOs for app consumption
struct YTSong {
    let id: String
    let title: String
    let artists: String
    let duration: String?
    let thumbnailUrl: String?
    let albumId: String?
    let albumName: String?
}

struct YTAlbum {
    let id: String
    let title: String
    let artists: String
    let year: String?
    let thumbnailUrl: String?
}

struct YTArtist {
    let id: String
    let name: String
    let thumbnailUrl: String?
}

struct YTPlaylist {
    let id: String              // browseId (without VL prefix)
    let name: String
    let author: String?
    let thumbnailUrl: String?
    let songCount: Int
    let playlistId: String?     // For radio playlists - use with next endpoint
}

// MARK: - Home Feed Models

struct HomePage {
    let chips: [HomeChip]
    let sections: [HomeSection]
    let continuation: String?
}

struct HomeChip: Equatable {
    let title: String
    let params: String?
    let isSelected: Bool
    
    static func == (lhs: HomeChip, rhs: HomeChip) -> Bool {
        lhs.title == rhs.title && lhs.params == rhs.params
    }
}

struct HomeSection {
    let title: String
    let label: String?
    let thumbnail: String?
    let items: [HomeItem]
    let browseId: String?  // For "See all" navigation
}

enum HomeItem {
    case song(YTSong)
    case album(YTAlbum)
    case artist(YTArtist)
    case playlist(YTPlaylist)
}

// MARK: - Explore Page Models

struct ExplorePage {
    let newReleaseAlbums: [YTAlbum]
    let moodAndGenres: [MoodAndGenre]
}

struct MoodAndGenre: Identifiable {
    let id: String
    let title: String
    let params: String?
    let color: String?
}

// MARK: - Audio Quality

enum AudioQuality: String {
    case auto = "auto"
    case low = "low"       // ~48kbps
    case medium = "medium" // ~128kbps
    case high = "high"     // ~256kbps

    var targetBitrate: Int? {
        switch self {
        case .auto: return nil
        case .low: return 48000
        case .medium: return 128000
        case .high: return 256000
        }
    }
}

class YouTubeMusic {
    static let shared = YouTubeMusic()
    private let client = InnerTubeClient.shared

    private init() {}

    // MARK: - Search

    func search(query: String, filter: SearchFilter = .all) async throws -> [SearchResult] {
        var body: [String: Any] = [
            "query": query
        ]

        // Only add params if not searching for all
        if filter != .all && !filter.params.isEmpty {
            body["params"] = filter.params
        }

        let response = try await client.makeRequest(
            endpoint: "search",
            body: body,
            responseType: SearchResponse.self
        )

        return parseSearchResults(response)
    }

    private func parseSearchResults(_ response: SearchResponse) -> [SearchResult] {
        guard let tabs = response.contents?.tabbedSearchResultsRenderer?.tabs,
              let sections = tabs.first?.tabRenderer?.content?.sectionListRenderer?.contents else {
            return []
        }

        var results: [SearchResult] = []

        for section in sections {
            if let shelf = section.musicShelfRenderer {
                results.append(contentsOf: parseShelf(shelf))
            } else if let cardShelf = section.musicCardShelfRenderer {
                results.append(contentsOf: parseCardShelf(cardShelf))
            }
        }

        return results
    }

    private func parseCardShelf(_ cardShelf: MusicCardShelfRenderer) -> [SearchResult] {
        guard let contentWrappers = cardShelf.contents else { return [] }

        return contentWrappers.compactMap { wrapper -> SearchResult? in
            guard let item = wrapper.musicResponsiveListItemRenderer else { return nil }
            return parseSearchItem(item)
        }
    }

    private func parseShelf(_ shelf: MusicShelfRenderer) -> [SearchResult] {
        guard let contentWrappers = shelf.contents else { return [] }

        return contentWrappers.compactMap { wrapper -> SearchResult? in
            guard let item = wrapper.musicResponsiveListItemRenderer else { return nil }
            return parseSearchItem(item)
        }
    }

    private func parseSearchItem(_ item: MusicShelfRenderer.MusicResponsiveListItemRenderer) -> SearchResult? {
        // Determine item type based on navigationEndpoint structure
        let isSong = item.navigationEndpoint == nil ||
                     item.navigationEndpoint?.watchEndpoint != nil ||
                     item.navigationEndpoint?.watchPlaylistEndpoint != nil

        let isPlaylist = item.navigationEndpoint?.browseEndpoint?.browseEndpointContextSupportedConfigs?
            .browseEndpointContextMusicConfig?.pageType == "MUSIC_PAGE_TYPE_PLAYLIST"

        let isAlbum = item.navigationEndpoint?.browseEndpoint?.browseEndpointContextSupportedConfigs?
            .browseEndpointContextMusicConfig?.pageType == "MUSIC_PAGE_TYPE_ALBUM" ||
            item.navigationEndpoint?.browseEndpoint?.browseEndpointContextSupportedConfigs?
            .browseEndpointContextMusicConfig?.pageType == "MUSIC_PAGE_TYPE_AUDIOBOOK"

        let isArtist = item.navigationEndpoint?.browseEndpoint?.browseEndpointContextSupportedConfigs?
            .browseEndpointContextMusicConfig?.pageType == "MUSIC_PAGE_TYPE_ARTIST" ||
            item.navigationEndpoint?.browseEndpoint?.browseEndpointContextSupportedConfigs?
            .browseEndpointContextMusicConfig?.pageType == "MUSIC_PAGE_TYPE_LIBRARY_ARTIST"

        let thumbnailUrl = item.thumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails?.last?.url

        // Extract text data from flexColumns if available
        let title = item.flexColumns?.first?.musicResponsiveListItemFlexColumnRenderer?.text?.combined ?? ""
        let subtitle = item.flexColumns?.dropFirst().first?.musicResponsiveListItemFlexColumnRenderer?.text?.combined ?? ""

        // Extract duration from fixedColumns (typically the first fixed column contains duration)
        let duration = item.fixedColumns?.first?.musicResponsiveListItemFlexColumnRenderer?.text?.combined

        if isSong {
            // For songs, try multiple places to find videoId
            // Priority: overlay first (has actual playable video ID), then navigationEndpoint, then playlistItemData
            var videoId: String?

            // Method 1: overlay endpoint (most reliable for search results - has actual YouTube video ID)
            if let overlayVideoId = item.overlay?.musicItemThumbnailOverlayRenderer?.content?
                   .musicPlayButtonRenderer?.playNavigationEndpoint?.watchEndpoint?.videoId {
                videoId = overlayVideoId
            }

            // Method 2: navigationEndpoint (fallback)
            if videoId == nil,
               let navVideoId = item.navigationEndpoint?.watchEndpoint?.videoId {
                videoId = navVideoId
            }

            // Method 3: playlistItemData (last resort - may contain Music-specific IDs)
            if videoId == nil,
               let playlistVideoId = item.playlistItemData?.videoId {
                videoId = playlistVideoId
            }

            guard let finalVideoId = videoId else {
                return nil
            }

            return .song(YTSong(
                id: finalVideoId,
                title: title,
                artists: subtitle,
                duration: duration,
                thumbnailUrl: thumbnailUrl,
                albumId: nil,
                albumName: nil
            ))
        } else if isArtist {
            // For artists, extract browseId from navigationEndpoint
            guard let browseId = item.navigationEndpoint?.browseEndpoint?.browseId else {
                return nil
            }

            return .artist(YTArtist(
                id: browseId,
                name: title,
                thumbnailUrl: thumbnailUrl
            ))
        } else if isAlbum {
            // For albums, extract browseId from navigationEndpoint
            guard let browseId = item.navigationEndpoint?.browseEndpoint?.browseId else {
                return nil
            }

            return .album(YTAlbum(
                id: browseId,
                title: title,
                artists: subtitle,
                year: nil,
                thumbnailUrl: thumbnailUrl
            ))
        } else if isPlaylist {
            // For playlists, extract browseId and remove "VL" prefix if present
            // This matches the Android implementation
            guard let browseId = item.navigationEndpoint?.browseEndpoint?.browseId else {
                return nil
            }

            let id = stripVL(browseId)

            // For search results, we don't have access to thumbnailOverlay, so playlistId will be nil
            // We'll handle radio playlists in the detail view using the id

            return .playlist(YTPlaylist(
                id: id,
                name: title,
                author: subtitle,
                thumbnailUrl: thumbnailUrl,
                songCount: 0,
                playlistId: nil
            ))
        }

        return nil
    }

    // MARK: - Player

    func getPlayer(videoId: String) async throws -> (response: PlayerResponse, clientType: InnerTubeClientType) {
        // Base body - include flags to pass age/region checks
        let baseBody: [String: Any] = [
            "videoId": videoId,
            "playlistId": "RDAMVM\(videoId)",
            "racyCheckOk": true,
            "contentCheckOk": true
        ]

        // Optimized client order based on 2025-2026 YouTube changes:
        // - IOS 20.42 and ANDROID 20.07 are the most reliable without PO Token (no login required)
        // - ANDROID_MUSIC now requires auth (LOGIN_REQUIRED without cookies), so only try when authenticated
        // - WEB clients now often need poToken and fail with UNPLAYABLE, so deprioritized
        // Player InnerTune: si hay cookie, ANDROID_MUSIC primero (age-restricted), luego IOS, luego TVHTML5+piped.
        // WEB_REMIX exige poToken → 403, por eso va el último aunque haya sesión.
        // ANDROID/IOS van sin auth (shouldSendAuth=false) y tiran 206 aunque estés logueado.
        var clients: [InnerTubeClientType] = []
        if client.hasBearer && !client.hasCookieAuth {
            // Bearer-only (OAuth without cookies): VISIONOS (no 1MB throttling) > TV (supports bearer)
            clients.append(contentsOf: [.visionOS, .tv, .tvEmbedded, .android, .ios])
        } else if client.isAuthenticated {
            // VISIONOS primero: sus URLs no sufren el muro de 1MB.
            clients.append(contentsOf: [.visionOS, .tv, .tvEmbedded, .androidMusic, .android, .ios])
        } else {
            // Unauthenticated: VISIONOS (sin throttling) > ANDROID > IOS
            clients.append(contentsOf: [.visionOS, .android, .ios, .tvEmbedded, .androidVR])
        }

        var lastError: Error?
        for clientType in clients {
            do {
                // Each attempt uses fresh body to avoid mutation side-effects
                var body = baseBody
                // Add playbackContext for better compatibility (helps with signatureTimestamp)
                body["playbackContext"] = [
                    "contentPlaybackContext": [
                        "html5Preference": "HTML5_PREF_WANTS",
                        "signatureTimestamp": 20325
                    ]
                ]

                let response = try await client.makeRequest(
                    endpoint: "player",
                    body: body,
                    clientType: clientType,
                    responseType: PlayerResponse.self
                )

                // Check playability status
                guard response.playabilityStatus?.status == "OK" else {
                    let reason = response.playabilityStatus?.reason ?? response.playabilityStatus?.status ?? "unknown"
                    print("⚠️ [YouTube API] Client \(clientType) not playable: \(reason)")
                    await MainActor.run { DebugLogger.shared.log("⚠️ player \(clientType) no reproducible: \(reason)") }
                    if response.playabilityStatus?.status == "LOGIN_REQUIRED" {
                        lastError = InnerTubeError.authenticationExpired
                    }
                    continue
                }

                // Check if we got streaming data with valid URLs or cipher
                if let streamingData = response.streamingData {
                    let hasUsableFormat: Bool = {
                        let check: ([PlayerResponse.StreamingData.Format]?) -> Bool = { fmts in
                            guard let fmts = fmts else { return false }
                            return fmts.contains(where: { $0.url != nil || $0.signatureCipher != nil || $0.cipher != nil })
                        }
                        return check(streamingData.adaptiveFormats) || check(streamingData.formats)
                    }()

                    if hasUsableFormat {
                        print("🎵 [YouTube API] Using client: \(clientType) for \(response.videoDetails?.title ?? "unknown")")
                        return (response, clientType)
                    } else {
                        print("⚠️ [YouTube API] Client \(clientType) has no usable formats")
                        await MainActor.run { DebugLogger.shared.log("⚠️ player \(clientType) sin formatos usables") }
                    }
                }
            } catch {
                lastError = error
                print("⚠️ [YouTube API] Client \(clientType) request failed: \(error)")
                await MainActor.run { DebugLogger.shared.log("❌ player \(clientType) err=\(error)") }
                continue
            }
        }

        if let authErr = lastError as? InnerTubeError, case .authenticationExpired = authErr {
            throw authErr
        }
        throw InnerTubeError.invalidResponse
    }

    func getStreamUrl(videoId: String) async throws -> (url: String, expiry: TimeInterval?, duration: TimeInterval?, clientType: InnerTubeClientType, loudnessDb: Double?) {
        let (playerResponse, usedClientType) = try await getPlayer(videoId: videoId)

        // Collect assets for n-decoding if available (mobile clients usually have no assets)
        var assetsResponse: PlayerResponse? = playerResponse
        if playerResponse.assets?.js == nil {
            // Try to fetch assets via WEB_REMIX as fallback (forceNoAuth to avoid 400 on player)
            do {
                let webBody: [String: Any] = [
                    "videoId": videoId,
                    "playlistId": "RDAMVM\(videoId)",
                    "racyCheckOk": true,
                    "contentCheckOk": true
                ]
                let webResponse = try await client.makeRequest(
                    endpoint: "player",
                    body: webBody,
                    clientType: .webRemix,
                    forceNoAuth: true,
                    responseType: PlayerResponse.self
                )
                if webResponse.assets?.js != nil {
                    assetsResponse = webResponse
                }
            } catch {
                // Silently continue without web player assets
            }
        }

        // Get correct duration from YouTube API
        var correctDuration: TimeInterval?
        if let lengthSeconds = playerResponse.videoDetails?.lengthSeconds,
           let duration = Double(lengthSeconds) {
            correctDuration = duration
            print("🎵 [YouTube API] lengthSeconds for \(playerResponse.videoDetails?.title ?? "unknown"): \(lengthSeconds)s")
        } else {
            print("⚠️ [YouTube API] No lengthSeconds in response for \(playerResponse.videoDetails?.title ?? "unknown")")
        }

        guard let streamingData = playerResponse.streamingData else {
            throw InnerTubeError.invalidResponse
        }

        // Get all audio formats - fallback to formats if adaptiveFormats empty
        var audioFormats = streamingData.adaptiveFormats?.filter { format in
            format.mimeType.contains("audio")
        } ?? []
        if audioFormats.isEmpty, let fallback = streamingData.formats?.filter({ $0.mimeType.contains("audio") }) {
            audioFormats = fallback
        }

        // Prefer iOS-compatible formats (MP4/AAC) over WebM/Opus
        let iosCompatibleFormats = audioFormats.filter { format in
            format.mimeType.contains("mp4") || format.mimeType.contains("m4a")
        }

        // Get quality preference
        let qualityPref = UserDefaults.standard.string(forKey: "audioQuality") ?? "auto"
        let quality = AudioQuality(rawValue: qualityPref) ?? .auto

        // Select format based on quality preference
        let selectedFormat: PlayerResponse.StreamingData.Format?

        if let targetBitrate = quality.targetBitrate {
            // User selected specific quality - find closest match by bitrate
            if !iosCompatibleFormats.isEmpty {
                selectedFormat = iosCompatibleFormats.min(by: { format1, format2 in
                    let diff1 = abs((format1.bitrate ?? 0) - targetBitrate)
                    let diff2 = abs((format2.bitrate ?? 0) - targetBitrate)
                    return diff1 < diff2
                })
            } else {
                selectedFormat = audioFormats.min(by: { format1, format2 in
                    let diff1 = abs((format1.bitrate ?? 0) - targetBitrate)
                    let diff2 = abs((format2.bitrate ?? 0) - targetBitrate)
                    return diff1 < diff2
                })
            }
        } else {
            // Auto quality - select highest bitrate (existing behavior)
            if !iosCompatibleFormats.isEmpty {
                selectedFormat = iosCompatibleFormats.max(by: { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) })
            } else {
                selectedFormat = audioFormats.max(by: { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) })
            }
        }

        guard let bestFormat = selectedFormat else {
            throw InnerTubeError.invalidResponse
        }

        print("🎵 [YouTube API] Selected format (quality: \(quality.rawValue)) - itag: \(bestFormat.itag ?? 0), mimeType: \(bestFormat.mimeType), bitrate: \(bestFormat.bitrate ?? 0), contentLength: \(bestFormat.contentLength ?? "unknown")")

        // Handle cipher when plain URL is absent (signatureCipher or cipher)
        let directUrl = bestFormat.url ?? decodeSignatureCipher(bestFormat.signatureCipher) ?? decodeSignatureCipher(bestFormat.cipher)

        guard let baseUrl = directUrl else {
            throw InnerTubeError.invalidResponse
        }

        // Attempt to deobfuscate throttling parameter (n param).
        // Un `n` sin decodificar = googlevideo corta ~1MB y luego 403 persistente.
        // Una URL SIN `n` no sufre throttling: es el caso bueno, no hay que "buscar" una con `n`.
        var (finalUrl, deciphered) = await ThrottlingDecipher.shared.deobfuscate(url: baseUrl, playerResponse: assetsResponse)
        await MainActor.run { DebugLogger.shared.log("🔍 streamUrl \(usedClientType) hasN=\(finalUrl.contains("n=")) deciphered=\(deciphered) itag=\(bestFormat.itag ?? 0)") }
        // VISIONOS queda EXCLUIDO del fallback: su `n` es válido (verificado: descarga
        // completa). Cambiarlo por una URL android sin `n` REINTRODUCIRÍA el muro de 1MB.
        if usedClientType != .visionOS, finalUrl.contains("n=") && !deciphered,
           let nfree = await fetchNFreeAudioUrl(videoId: videoId) {
            finalUrl = nfree
            await MainActor.run { DebugLogger.shared.log("✅ streamUrl usando alternativa sin `n` (sin throttling)") }
        }
        // ratebypass=yes mitiga throttling residual en googlevideo
        if !finalUrl.contains("ratebypass") {
            finalUrl += finalUrl.contains("?") ? "&ratebypass=yes" : "?ratebypass=yes"
        }

        // Calculate expiry time
        var expiryTime: TimeInterval?
        if let expiresInSeconds = streamingData.expiresInSeconds,
           let seconds = Double(expiresInSeconds) {
            expiryTime = Date().timeIntervalSince1970 + seconds
        }

        // Extract loudness for normalization
        let loudnessDb = bestFormat.loudnessDb

        return (url: finalUrl, expiry: expiryTime, duration: correctDuration, clientType: usedClientType, loudnessDb: loudnessDb)
    }

    // Get stream URL optimized for downloading (with range parameter)
    func getStreamUrlForDownload(videoId: String) async throws -> (url: String, contentLength: Int64, clientType: InnerTubeClientType) {
        let (playerResponse, usedClientType) = try await getPlayer(videoId: videoId)

        guard let streamingData = playerResponse.streamingData else {
            throw InnerTubeError.invalidResponse
        }

        // Get all audio formats - fallback to formats if needed
        var audioFormats = streamingData.adaptiveFormats?.filter { format in
            format.mimeType.contains("audio")
        } ?? []
        if audioFormats.isEmpty, let fallback = streamingData.formats?.filter({ $0.mimeType.contains("audio") }) {
            audioFormats = fallback
        }

        // If still empty, try any format with contentLength
        if audioFormats.isEmpty {
            audioFormats = (streamingData.adaptiveFormats ?? []) + (streamingData.formats ?? [])
        }

        // Prefer iOS-compatible formats (MP4/AAC)
        let iosCompatibleFormats = audioFormats.filter { format in
            format.mimeType.contains("mp4") || format.mimeType.contains("m4a")
        }

        // Select best format
        let selectedFormat: PlayerResponse.StreamingData.Format?
        if !iosCompatibleFormats.isEmpty {
            selectedFormat = iosCompatibleFormats.max(by: { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) })
        } else {
            selectedFormat = audioFormats.max(by: { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) })
        }

        guard let bestFormat = selectedFormat else {
            throw InnerTubeError.invalidResponse
        }

        let contentLength: Int64 = Int64(bestFormat.contentLength ?? "0") ?? 0

        // Get base URL (handle cipher if needed)
        let baseUrl = bestFormat.url ?? decodeSignatureCipher(bestFormat.signatureCipher) ?? decodeSignatureCipher(bestFormat.cipher)

        guard var url = baseUrl else {
            throw InnerTubeError.invalidResponse
        }

        // Misma protección anti-throttling que streaming (`n` sin decodificar → 403 ~1MB),
        // excepto VISIONOS cuyo `n` es válido (verificado: descarga completa).
        let (det, ok) = await ThrottlingDecipher.shared.deobfuscate(url: url, playerResponse: playerResponse)
        url = det
        if usedClientType != .visionOS, url.contains("n=") && !ok,
           let nfree = await fetchNFreeAudioUrl(videoId: videoId) {
            url = nfree
        }
        if !url.contains("ratebypass") {
            url += url.contains("?") ? "&ratebypass=yes" : "?ratebypass=yes"
        }

        // Do NOT add &range query here – googlevideo now rejects full-range query (403)
        // DownloadManager will fetch via Range header in chunks (see DownloadManager.performChunkedDownload)
        // This keeps URL clean for both streaming (AVPlayer via CustomResourceLoader) and chunked download

        return (url: url, contentLength: contentLength, clientType: usedClientType)
    }

    /// Busca una URL de audio SIN parámetro `n` (iOS/Android noAuth): esas URLs no
    /// sufren throttling y no necesitan decipher. Fallback cuando el `n` no se pudo decodificar.
    private func fetchNFreeAudioUrl(videoId: String) async -> String? {
        let body: [String: Any] = [
            "videoId": videoId,
            "racyCheckOk": true,
            "contentCheckOk": true
        ]
        for ctype in [InnerTubeClientType.ios, .android] as [InnerTubeClientType] {
            do {
                let resp: PlayerResponse = try await client.makeRequest(
                    endpoint: "player", body: body, clientType: ctype,
                    forceNoAuth: true, responseType: PlayerResponse.self
                )
                guard resp.playabilityStatus?.status == "OK" else { continue }
                let fmts = (resp.streamingData?.adaptiveFormats ?? []) + (resp.streamingData?.formats ?? [])
                if let f = selectBestAudioFormat(fmts),
                   let u = f.url ?? decodeSignatureCipher(f.signatureCipher) ?? decodeSignatureCipher(f.cipher),
                   !u.contains("n=") {
                    let clean = u.replacingOccurrences(of: "\\u0026", with: "&")
                        .replacingOccurrences(of: "\\u003d", with: "=")
                        .replacingOccurrences(of: "\\/", with: "/")
                    return clean
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func selectBestAudioFormat(_ formats: [PlayerResponse.StreamingData.Format]) -> PlayerResponse.StreamingData.Format? {
        let audioFormats = formats.filter { $0.mimeType.contains("audio") }
        let iosCompatibleFormats = audioFormats.filter { $0.mimeType.contains("mp4") || $0.mimeType.contains("m4a") }
        if !iosCompatibleFormats.isEmpty {
            return iosCompatibleFormats.max(by: { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) })
        }
        return audioFormats.max(by: { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) })
    }

    private func decodeSignatureCipher(_ cipher: String?) -> String? {
        guard let cipher = cipher else { return nil }
        let params = parseQuery(cipher)

        guard let url = params["url"] else { return nil }

        // If signature parameter exists, append it; otherwise return url
        if let s = params["s"] {
            let sp = params["sp"] ?? "signature"
            var components = URLComponents(string: url)
            var queryItems = components?.queryItems ?? []
            queryItems.append(URLQueryItem(name: sp, value: s))
            components?.queryItems = queryItems
            return components?.string
        }

        return url
    }

    private func parseQuery(_ query: String) -> [String: String] {
        var dict: [String: String] = [:]
        let items = query.split(separator: "&")
        for item in items {
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let key = pair[0].removingPercentEncoding ?? pair[0]
            let value = pair[1].removingPercentEncoding ?? pair[1]
            dict[key] = value
        }
        return dict
    }

    // MARK: - Browse

    func browse(browseId: String) async throws -> BrowseResponse {
        let body: [String: Any] = [
            "browseId": browseId
        ]

        // Contenido público: si hay Bearer OAuth, los intentos con auth dan 400 (Bearer no vale para IOS/WEB_REMIX).
        // Tu log: Bearer+ios/webRemix → 400, noAuth → OK. Por eso para público se prueba noAuth primero si hay Bearer.
        // Para librería privada se usa browseAuthenticated() aparte (sin fallback público).
        let hasBearer = OAuthManager.bearerHeaderSync != nil
        let attempts: [(InnerTubeClientType, Bool)] = client.isAuthenticated
            ? (hasBearer
                ? [(.webRemix, true), (.ios, true), (.android, true), (.ios, false), (.webRemix, false)]
                : [(.webRemix, false), (.ios, false), (.webRemix, true), (.ios, true), (.android, true)])
            : [(.webRemix, false)]
        var lastErr: Error = InnerTubeError.authenticationExpired
        for (ctype, noAuth) in attempts {
            do {
                // -999 cancelled = vista cerrada, no seguir probando (evita cascada de 5 logs)
                if Task.isCancelled { throw CancellationError() }
                await MainActor.run { DebugLogger.shared.log("📚 browse \(browseId) try \(ctype) forceNoAuth=\(noAuth)") }
                let resp: BrowseResponse = try await client.makeRequest(
                    endpoint: "browse",
                    body: body,
                    clientType: ctype,
                    forceNoAuth: noAuth,
                    responseType: BrowseResponse.self
                )
                await MainActor.run { DebugLogger.shared.log("📚 browse \(browseId) OK via \(ctype) noAuth=\(noAuth)") }
                return resp
            } catch let e as URLError where e.code == .cancelled {
                throw e
            } catch {
                // NSURLError -999 también es cancelación de SwiftUI (.task re-ejecutado)
                if (error as NSError).code == -999 { throw error }
                lastErr = error
                await MainActor.run { DebugLogger.shared.log("❌ browse \(browseId) via \(ctype) noAuth=\(noAuth) err=\(error)") }
                continue
            }
        }
        throw lastErr
    }

    /// Browse solo-autenticado para librería privada (VLLM, FEmusic_liked_playlists, historial).
    /// NO hace fallback a noAuth: si todo falla, lanza para que Sync muestre error real en vez de lista vacía.
    /// Detecta sign-in prompts en respuesta 200 y prueba siguiente cliente.
    /// Orden según mecanismo (evidencia de logs):
    /// - Bearer-only (OAuth sin cookies): TV primero (único que acepta Bearer),
    ///   luego ANDROID_MUSIC, luego IOS. WEB_REMIX+Bearer da 400 sistemático → último.
    /// - Solo cookies: WEB_REMIX (SAPISIDHASH) primero, luego ANDROID_MUSIC, luego IOS.
    ///   TV+cookies da 401 (TV exige Bearer) → se omite.
    func browseAuthenticated(browseId: String) async throws -> BrowseResponse {
        await OAuthManager.shared.refreshIfNeeded()
        let body: [String: Any] = ["browseId": browseId]
        let bearer = client.hasBearer, cookies = client.hasCookieAuth
        let attempts: [(InnerTubeClientType, Bool)]
        if bearer && !cookies {
            attempts = [(.tv, false)]
        } else if cookies && !bearer {
            attempts = [(.webRemix, false), (.androidMusic, false), (.ios, false)]
        } else {
            attempts = [(.tv, false), (.webRemix, false), (.androidMusic, false), (.ios, false)]
        }
        var lastErr: Error = InnerTubeError.authenticationExpired
        for (ctype, noAuth) in attempts {
            do {
                if Task.isCancelled { throw CancellationError() }
                await MainActor.run { DebugLogger.shared.log("📚 browseAuth \(browseId) try \(ctype)") }
                let resp: BrowseResponse = try await client.makeRequest(
                    endpoint: "browse", body: body, clientType: ctype,
                    forceNoAuth: noAuth, responseType: BrowseResponse.self
                )
                if hasSignInPrompt(resp) {
                    await MainActor.run { DebugLogger.shared.log("⚠️ browseAuth \(browseId) via \(ctype) tiene sign-in prompt, probando siguiente") }
                    lastErr = InnerTubeError.authenticationExpired
                    continue
                }
                // Check if response has any content
                let hasTypedContent = resp.contents?.singleColumnBrowseResultsRenderer != nil
                    || resp.contents?.twoColumnBrowseResultsRenderer != nil
                    || resp.contents?.sectionListRenderer != nil
                if !hasTypedContent && resp.contents == nil {
                    await MainActor.run { DebugLogger.shared.log("⚠️ browseAuth \(browseId) via \(ctype) returned empty result, trying next client") }
                    lastErr = InnerTubeError.authenticationExpired
                    continue
                }
                await MainActor.run { DebugLogger.shared.log("📚 browseAuth \(browseId) OK via \(ctype)") }
                return resp
            } catch let e as URLError where e.code == .cancelled {
                throw e
            } catch {
                if (error as NSError).code == -999 { throw error }
                lastErr = error
                await MainActor.run { DebugLogger.shared.log("❌ browseAuth \(browseId) via \(ctype) err=\(error)") }
                continue
            }
        }
        throw lastErr
    }

    private func hasSignInPrompt(_ resp: BrowseResponse) -> Bool {
        if let sections = resp.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents {
            for section in sections {
                if let msg = section.itemSectionRenderer?.contents?.first?.messageRenderer,
                   msg.button?.buttonRenderer?.navigationEndpoint?.signInEndpoint != nil {
                    return true
                }
            }
        }
        if let twoColumn = resp.contents?.twoColumnBrowseResultsRenderer,
           let tabs = twoColumn.tabs,
           let sections = tabs.first?.tabRenderer?.content?.sectionListRenderer?.contents {
            for section in sections {
                if let msg = section.itemSectionRenderer?.contents?.first?.messageRenderer,
                   msg.button?.buttonRenderer?.navigationEndpoint?.signInEndpoint != nil {
                    return true
                }
            }
        }
        return false
    }

    /// Raw auth (TV primero) para parseo genérico cuando el modelo tipado no cubre el shape TV.
    func browseRawAuthenticated(browseId: String) async throws -> [String: Any] {
        let body: [String: Any] = ["browseId": browseId]
        var lastErr: Error = InnerTubeError.authenticationExpired
        let bearer = client.hasBearer, cookies = client.hasCookieAuth
        let order: [InnerTubeClientType]
        if bearer && !cookies {
            order = [.tv]
        } else if cookies && !bearer {
            order = [.webRemix, .androidMusic, .ios]
        } else {
            order = [.tv, .webRemix, .androidMusic, .ios]
        }
        var firstDict: [String: Any]?
        for ctype in order {
            do {
                if Task.isCancelled { throw CancellationError() }
                let dict = try await client.makeRawRequest(endpoint: "browse", body: body, clientType: ctype, forceNoAuth: false)
                let songsFound = rawSongs(dict).count
                let playlistsFound = rawPlaylists(dict).count
                let albumsFound = rawAlbums(dict).count
                let artistsFound = rawArtists(dict).count
                await MainActor.run { DebugLogger.shared.log("📚 rawAuth \(browseId) OK via \(ctype) keys=\(dict.keys.sorted().prefix(6)) songs=\(songsFound) playlists=\(playlistsFound) albums=\(albumsFound) artists=\(artistsFound)") }
                // Muestra SIEMPRE (1500 chars): los casos mixtos (p.ej. playlists=4 pero
                // albums=0) son los que necesitan diagnóstico y antes quedaban sin dump.
                if let data = try? JSONSerialization.data(withJSONObject: dict),
                   let sample = String(data: data, encoding: .utf8) {
                    await MainActor.run { DebugLogger.shared.log("🔍 rawAuth \(browseId) sample=\(sample.prefix(1500))") }
                }
                if songsFound == 0 && playlistsFound == 0 && albumsFound == 0 && artistsFound == 0 {
                    // Vacío (shell TV, sign-in prompt...): probar siguiente cliente en vez
                    // de devolver vacío. Se guarda el primero por si todos dan vacío.
                    if firstDict == nil { firstDict = dict }
                    let keys2 = Self.deepKeys(dict, depth: 8)
                    await MainActor.run { DebugLogger.shared.log("🔍 rawAuth \(browseId) deepKeys=\(keys2.prefix(40))") }
                    continue
                }
                return dict
            } catch let e as URLError where e.code == .cancelled {
                throw e
            } catch {
                if (error as NSError).code == -999 { throw error }
                lastErr = error
                continue
            }
        }
        // Todos vacíos o con error: devolver el primero (mismo comportamiento que antes)
        if let first = firstDict { return first }
        throw lastErr
    }

    /// Raw PÚBLICO sin auth (webRemix): para fallbacks de contenido público cuando
    /// hay sesión pero el raw autenticado falla (p. ej. Bearer 400s).
    func browseRawPublic(browseId: String) async throws -> [String: Any] {
        let body: [String: Any] = ["browseId": browseId]
        return try await client.makeRawRequest(
            endpoint: "browse", body: body, clientType: .webRemix, forceNoAuth: true
        )
    }

    static func deepKeys(_ node: Any, depth: Int) -> [String] {
        guard depth > 0 else { return [] }
        var result: [String] = []
        if let d = node as? [String: Any] {
            for (k, v) in d {
                result.append(k)
                if v is [String: Any] || v is [Any] {
                    result.append(contentsOf: deepKeys(v, depth: depth - 1).map { "\(k).\($0)" })
                }
            }
        } else if let a = node as? [Any], let first = a.first {
            result.append(contentsOf: deepKeys(first, depth: depth - 1).map { "[].\($0)" })
        }
        return result
    }

    // MARK: - Raw JSON helpers (recorrido genérico, independiente del shape TV/WEB/IOS)

    private func rawTexts(_ node: Any?) -> [String] {
        guard let d = node as? [String: Any] else { return [] }
        if let runs = d["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }
        }
        if let s = d["simpleText"] as? String { return [s] }
        return []
    }

    private func rawThumb(_ node: Any?) -> String? {
        guard let d = node as? [String: Any] else { return nil }
        // musicThumbnailRenderer.thumbnail.thumbnails[].url  o thumbnail.thumbnails[].url
        let lists: [[String: Any]] = [
            ((d["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? [],
            (d["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? [],
            d["thumbnails"] as? [[String: Any]] ?? []
        ].flatMap { $0 }
        return (lists.last?["url"] as? String) ?? (lists.first?["url"] as? String)
    }

    private func walk(_ node: Any, visit: ([String: Any]) -> Void) {
        if let d = node as? [String: Any] {
            visit(d)
            for v in d.values { walk(v, visit: visit) }
        } else if let a = node as? [Any] {
            for v in a { walk(v, visit: visit) }
        }
    }

    /// Extrae playlists (browseId VL*/PL* + título) de cualquier shape TV/WEB/IOS.
    private func rawPlaylists(_ root: [String: Any]) -> [YTPlaylist] {
        var out: [YTPlaylist] = []
        var seen = Set<String>()
        walk(root) { d in
            var browseId: String?
            if let bid = d["browseId"] as? String { browseId = bid }
            if browseId == nil, let cid = d["contentId"] as? String { browseId = cid }
            if browseId == nil {
                for (k, val) in d where k.lowercased().contains("endpoint") || k.lowercased().contains("command") || k.lowercased().contains("select") {
                    if let ed = val as? [String: Any] {
                        if let be = (ed["browseEndpoint"] ?? ed["navigationEndpoint"]) as? [String: Any],
                           let bid = be["browseId"] as? String {
                            browseId = bid; break
                        }
                    }
                }
            }

            guard let bid = browseId else { return }
            if bid == "FEmusic_liked_playlists" || bid == "FEmusic_history" || bid == "FEmusic_explore" { return }

            // Playlist IDs start with VL, PL, MPSP, RD, UC, VLLM, or SE or length != 11
            let isPlaylist = bid.hasPrefix("VL") || bid.hasPrefix("PL") || bid.hasPrefix("MPSP") || bid == "VLLM" || bid == "SE" || bid.hasPrefix("RD") || bid.count != 11
            guard isPlaylist else { return }

            var title = rawTexts(d["title"]).joined()
            if title.isEmpty { title = rawTexts(d["header"]).joined() }
            if title.isEmpty, let t = d["title"] as? String { title = t }
            if title.isEmpty { return }

            let pid = bid.hasPrefix("VL") ? stripVL(bid) : bid
            guard !seen.contains(pid) else { return }
            seen.insert(pid)

            let subtitle = rawTexts(d["subtitle"]).joined(separator: " ")
            let thumb = rawThumb(d["header"]) ?? rawThumb(d["thumbnailRenderer"]) ?? rawThumb(d["thumbnail"])
            var count = 0
            for tok in subtitle.components(separatedBy: " ") {
                if let n = Int(tok) { count = n; break }
            }
            out.append(YTPlaylist(id: pid, name: title, author: subtitle.isEmpty ? nil : subtitle, thumbnailUrl: thumb, songCount: count, playlistId: nil))
        }
        return out
    }

    /// Extrae canciones (videoId + título) de cualquier shape TV/WEB/IOS.
    private func rawSongs(_ root: [String: Any]) -> [YTSong] {
        var out: [YTSong] = []
        var seen = Set<String>()
        walk(root) { d in
            var vid: String?
            // 0. contentId or videoId (MUST be 11 chars long for a YouTube video!)
            if let cid = (d["videoId"] ?? d["contentId"]) as? String {
                let isPlaylistId = cid.hasPrefix("PL") || cid.hasPrefix("VL") || cid.hasPrefix("MPSP") || cid.hasPrefix("RD") || cid.hasPrefix("UC") || cid == "VLLM" || cid == "FEmusic_liked_playlists"
                if cid.count == 11 && !isPlaylistId {
                    vid = cid
                }
            }
            // 1. overlay.playNavigationEndpoint.watchEndpoint.videoId
            if vid == nil, let ov = ((d["overlay"] as? [String: Any])?["musicItemThumbnailOverlayRenderer"] as? [String: Any])?["content"] as? [String: Any],
               let pb = ov["musicPlayButtonRenderer"] as? [String: Any],
               let pne = pb["playNavigationEndpoint"] as? [String: Any],
               let we = pne["watchEndpoint"] as? [String: Any],
               let v = we["videoId"] as? String, v.count == 11 { vid = v }
            // 2. playlistItemData.videoId
            if vid == nil, let pid = d["playlistItemData"] as? [String: Any], let v = pid["videoId"] as? String, v.count == 11 { vid = v }
            // 3. navigationEndpoint.watchEndpoint.videoId
            if vid == nil, let nav = d["navigationEndpoint"] as? [String: Any],
               let we = nav["watchEndpoint"] as? [String: Any],
               let v = we["videoId"] as? String, v.count == 11 { vid = v }
            // 4. playlistPanelVideoRenderer (TV/queue) or direct videoId
            if vid == nil, let v = d["videoId"] as? String, v.count == 11 { vid = v }
            // 4b. watchEndpoint under any *Endpoint key
            if vid == nil {
                for (k, val) in d where k.hasSuffix("Endpoint") || k.hasSuffix("Command") {
                    if let ed = val as? [String: Any] {
                        if let we = (ed["watchEndpoint"] ?? ed["navigationEndpoint"]) as? [String: Any],
                           let v = (we["videoId"] ?? we["contentId"]) as? String, v.count == 11 { vid = v; break }
                    }
                }
            }

            guard let v = vid, !seen.contains(v) else { return }

            // Title extraction
            var title = ""
            if let flex = d["flexColumns"] as? [[String: Any]], let first = flex.first,
               let r = first["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any] {
                title = rawTexts(r["text"]).joined()
            }
            if title.isEmpty, let hdr = d["header"] as? [String: Any] { title = rawTexts(hdr).joined() }
            if title.isEmpty { title = rawTexts(d["title"]).joined() }
            if title.isEmpty { title = rawTexts(d["header"]).joined() }
            if title.isEmpty { title = rawTexts(d["name"]).joined() }
            if title.isEmpty { title = rawTexts(d["labelText"]).joined() }
            if title.isEmpty { title = rawTexts(d["titleText"]).joined() }
            if title.isEmpty, let t = d["title"] as? String { title = t }

            guard !title.isEmpty else { return }
            seen.insert(v)

            // Artists extraction
            var artists = ""
            if let flex = d["flexColumns"] as? [[String: Any]], flex.count > 1,
               let r = flex[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any] {
                artists = rawTexts(r["text"]).joined()
            }
            if artists.isEmpty { artists = rawTexts(d["subtitle"]).joined() }
            if artists.isEmpty { artists = rawTexts(d["longBylineText"]).joined() }
            if artists.isEmpty { artists = rawTexts(d["shortBylineText"]).joined() }

            // Thumbnail extraction
            let thumb = rawThumb(d["header"]) ?? rawThumb(d["thumbnail"])

            out.append(YTSong(id: v, title: title, artists: artists, duration: nil, thumbnailUrl: thumb, albumId: nil, albumName: nil))
        }
        return out
    }

    func getAlbum(browseId: String) async throws -> (YTAlbum, [YTSong]) {
        let response: BrowseResponse
        if client.isAuthenticated {
            do {
                response = try await browseAuthenticated(browseId: browseId)
            } catch {
                response = try await browse(browseId: browseId)
            }
        } else {
            response = try await browse(browseId: browseId)
        }

        // Try different header types
        var headerTitle: String = ""
        var headerSubtitle: String = ""
        var thumbnailUrl: String?

        if let detailHeader = response.header?.musicDetailHeaderRenderer {
            headerTitle = detailHeader.title?.combined ?? ""
            headerSubtitle = detailHeader.subtitle?.combined ?? ""
            thumbnailUrl = detailHeader.thumbnail?.croppedSquareThumbnailRenderer?.thumbnail?.thumbnails?.last?.url
        } else if let immersiveHeader = response.header?.musicImmersiveHeaderRenderer {
            headerTitle = immersiveHeader.title?.combined ?? ""
            headerSubtitle = immersiveHeader.description?.combined ?? ""
            thumbnailUrl = immersiveHeader.thumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails?.last?.url
        } else if let visualHeader = response.header?.musicVisualHeaderRenderer {
            headerTitle = visualHeader.title?.combined ?? ""
            headerSubtitle = ""
            thumbnailUrl = visualHeader.foregroundThumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails?.last?.url
        }
        
        // If no header found, try to extract from twoColumnBrowseResultsRenderer BEFORE creating album
        if headerTitle.isEmpty || thumbnailUrl == nil {
            if let twoColumn = response.contents?.twoColumnBrowseResultsRenderer,
               let firstTab = twoColumn.tabs?.first,
               let sections = firstTab.tabRenderer?.content?.sectionListRenderer?.contents,
               let headerRenderer = sections.first?.musicResponsiveHeaderRenderer {
                if headerTitle.isEmpty {
                    headerTitle = headerRenderer.title?.combined ?? ""
                }
                if headerSubtitle.isEmpty {
                    headerSubtitle = headerRenderer.straplineTextOne?.combined ?? headerRenderer.subtitle?.combined ?? ""
                }
                if thumbnailUrl == nil {
                    // Correct path: thumbnail -> musicThumbnailRenderer -> thumbnail -> thumbnails
                    thumbnailUrl = headerRenderer.thumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails?.last?.url
                }
            }
        }
        
        // Final fallback
        if headerTitle.isEmpty {
            headerTitle = "Album"
        }

        // Create album object with extracted metadata
        let album = YTAlbum(
            id: browseId,
            title: headerTitle,
            artists: headerSubtitle,
            year: nil,
            thumbnailUrl: thumbnailUrl
        )

        var songs: [YTSong] = []

        // Try twoColumnBrowseResultsRenderer (main albums path - matches Android)
        if let twoColumn = response.contents?.twoColumnBrowseResultsRenderer {
            // Try secondaryContents first (main song list location)
            if let playlistShelf = twoColumn.secondaryContents?.sectionListRenderer?.contents?.first?.musicPlaylistShelfRenderer {
                if let shelfContents = playlistShelf.contents {
                    for content in shelfContents {
                        if let item = content.musicResponsiveListItemRenderer,
                           let song = parseSearchItem(item) {
                            if case .song(let ytSong) = song {
                                songs.append(ytSong)
                            }
                        }
                    }
                }
            } else {
                // Try musicShelfRenderer instead
                if let musicShelf = twoColumn.secondaryContents?.sectionListRenderer?.contents?.first?.musicShelfRenderer {
                    if let shelfContents = musicShelf.contents {
                        for (index, content) in shelfContents.enumerated() {
                            if let item = content.musicResponsiveListItemRenderer {
                                if let song = parseSearchItem(item) {
                                    if case .song(let ytSong) = song {
                                        songs.append(ytSong)
                                    }
                                } else {
                                    // parseSearchItem failed - let's try direct extraction
                                    let title = item.flexColumns?.first?.musicResponsiveListItemFlexColumnRenderer?.text?.combined ?? ""
                                    var videoId: String?
                                    
                                    // Try overlay first
                                    if let overlayId = item.overlay?.musicItemThumbnailOverlayRenderer?.content?.musicPlayButtonRenderer?.playNavigationEndpoint?.watchEndpoint?.videoId {
                                        videoId = overlayId
                                    }
                                    // Try playlistItemData
                                    if videoId == nil, let playlistId = item.playlistItemData?.videoId {
                                        videoId = playlistId
                                    }
                                    
                                    if let vid = videoId, !title.isEmpty {
                                        let ytSong = YTSong(
                                            id: vid,
                                            title: title,
                                            artists: item.flexColumns?.dropFirst().first?.musicResponsiveListItemFlexColumnRenderer?.text?.combined ?? "",
                                            duration: item.fixedColumns?.first?.musicResponsiveListItemFlexColumnRenderer?.text?.combined,
                                            thumbnailUrl: item.thumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails?.last?.url,
                                            albumId: nil,
                                            albumName: nil
                                        )
                                        songs.append(ytSong)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Try sectionListRenderer (direct contents)
        if songs.isEmpty, let sections = response.contents?.sectionListRenderer?.contents {
            for section in sections {
                if let shelfContents = section.musicShelfRenderer?.contents {
                    for wrapper in shelfContents {
                        if let item = wrapper.musicResponsiveListItemRenderer,
                           let song = parseSearchItem(item) {
                            if case .song(let ytSong) = song {
                                songs.append(ytSong)
                            }
                        }
                    }
                }
            }
        }
        
        // Try singleColumnBrowseResultsRenderer (alternative path)
        if songs.isEmpty, let tabs = response.contents?.singleColumnBrowseResultsRenderer?.tabs {
            for tab in tabs {
                if let sections = tab.tabRenderer?.content?.sectionListRenderer?.contents {
                    for section in sections {
                        if let shelfContents = section.musicShelfRenderer?.contents {
                            for wrapper in shelfContents {
                                if let item = wrapper.musicResponsiveListItemRenderer,
                                   let song = parseSearchItem(item) {
                                    if case .song(let ytSong) = song {
                                        songs.append(ytSong)
                                    }
                                }
                            }
                        }
                        
                        if let playlistContents = section.musicPlaylistShelfRenderer?.contents {
                            for content in playlistContents {
                                if let item = content.musicResponsiveListItemRenderer,
                                   let song = parseSearchItem(item) {
                                    if case .song(let ytSong) = song {
                                        songs.append(ytSong)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Raw fallback if structured response didn't yield songs
        if songs.isEmpty {
            do {
                let raw: [String: Any]
                if client.isAuthenticated {
                    do {
                        raw = try await browseRawAuthenticated(browseId: browseId)
                    } catch {
                        raw = try await browseRawPublic(browseId: browseId)
                    }
                } else {
                    raw = try await browseRawPublic(browseId: browseId)
                }
                let rawList = rawSongs(raw)
                if !rawList.isEmpty {
                    await MainActor.run { DebugLogger.shared.log("📀 raw fallback album \(browseId) songs=\(rawList.count)") }
                    songs = rawList
                }
            } catch {}
        }
        
        // Inject album info (thumbnail, albumId, albumName) into each song
        let songsWithAlbumInfo = songs.map { song in
            YTSong(
                id: song.id,
                title: song.title,
                artists: song.artists,
                duration: song.duration,
                thumbnailUrl: song.thumbnailUrl ?? thumbnailUrl,  // Use album thumbnail as fallback
                albumId: browseId,
                albumName: headerTitle
            )
        }
        
        return (album, songsWithAlbumInfo)
    }

    func getPlaylist(browseId: String) async throws -> (YTPlaylist, [YTSong]) {
        // Si hay sesión, primero prueba autenticado (TV/IOS/WEB_REMIX con Bearer/cookies) para listas privadas (VLLM).
        // Si falla, cae a browse público para listas públicas.
        let response: BrowseResponse
        if client.isAuthenticated {
            // IDs privados: el browse público nunca puede funcionar (VLLM/FEmusic_*
            // sin auth = sign-in → authenticationExpired). Ir directo a parse+raw.
            let isPrivateId = browseId == "VLLM" || browseId.hasPrefix("FEmusic_")
            do {
                let ar = try await browseAuthenticated(browseId: browseId)
                // Shell TV (Bearer en playlist PÚBLICA): HTTP 200 sin contenido parseable
                // (ni header, ni twoColumn, ni singleColumn). Tratar como fallo para caer
                // al browse público en vez de devolver lista vacía / invalidResponse.
                if !isPrivateId && ar.header == nil && ar.contents?.twoColumnBrowseResultsRenderer == nil
                    && ar.contents?.singleColumnBrowseResultsRenderer == nil
                    && ar.contents?.sectionListRenderer == nil {
                    await MainActor.run { DebugLogger.shared.log("⚠️ getPlaylist \(browseId) shell authed sin contenido, probando público") }
                    throw InnerTubeError.invalidResponse
                }
                response = ar
            } catch {
                // IDs privados: no reintentar en público (solo daría sign-in/authExpired)
                if isPrivateId { throw error }
                await MainActor.run { DebugLogger.shared.log("⚠️ getPlaylist \(browseId) auth falló (\(error)), probando público") }
                response = try await browse(browseId: browseId)
            }
        } else {
            response = try await browse(browseId: browseId)
        }

        // Check for auth errors (when authenticated but cookies expired, YouTube returns sign-in prompt)
        if let sections = response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents {
            for section in sections {
                if let msg = section.itemSectionRenderer?.contents?.first?.messageRenderer,
                   msg.button?.buttonRenderer?.navigationEndpoint?.signInEndpoint != nil {
                    throw InnerTubeError.authenticationExpired
                }
            }
        }
        // Also check twoColumn tabs for sign-in
        if let twoColumn = response.contents?.twoColumnBrowseResultsRenderer,
           let tabs = twoColumn.tabs,
           let sections = tabs.first?.tabRenderer?.content?.sectionListRenderer?.contents {
            for section in sections {
                if let msg = section.itemSectionRenderer?.contents?.first?.messageRenderer,
                   msg.button?.buttonRenderer?.navigationEndpoint?.signInEndpoint != nil {
                    throw InnerTubeError.authenticationExpired
                }
            }
        }

        // For twoColumnBrowseResultsRenderer playlists (without top-level header)
        if let twoColumn = response.contents?.twoColumnBrowseResultsRenderer, response.header == nil {

            // Use browseId to construct a basic playlist
            let playlist = YTPlaylist(
                id: browseId,
                name: browseId, // Will be the actual playlist name from the UI
                author: nil,
                thumbnailUrl: nil,
                songCount: 0,
                playlistId: nil
            )

            var songs: [YTSong] = []
            var continuationToken: String? = nil

            // Try to get songs from tabs (matching Android implementation)
            // First try: tabs -> sectionListRenderer -> musicShelfRenderer or musicPlaylistShelfRenderer
            if let tabs = twoColumn.tabs,
               let firstTab = tabs.first,
               let sections = firstTab.tabRenderer?.content?.sectionListRenderer?.contents {
                // Try musicShelfRenderer first
                if let shelfRenderer = sections.first?.musicShelfRenderer {
                    if let shelfContents = shelfRenderer.contents {
                        for content in shelfContents {
                            if let item = content.musicResponsiveListItemRenderer,
                               let song = parseSearchItem(item) {
                                if case .song(let ytSong) = song {
                                    songs.append(ytSong)
                                }
                            }
                        }
                    }
                    continuationToken = shelfRenderer.continuations?.first?.nextContinuationData?.continuation
                }
                // Try musicPlaylistShelfRenderer
                else if let playlistRenderer = sections.first?.musicPlaylistShelfRenderer {
                    if let playlistContents = playlistRenderer.contents {
                        for content in playlistContents {
                            // Check if this is a continuation item
                            if let continuationItem = content.continuationItemRenderer {
                                let token = continuationItem.continuationEndpoint?.continuationCommand?.token
                                if token != nil {
                                    continuationToken = token
                                }
                            }
                            // Otherwise parse as song
                            else if let item = content.musicResponsiveListItemRenderer,
                               let song = parseSearchItem(item) {
                                if case .song(let ytSong) = song {
                                    songs.append(ytSong)
                                }
                            }
                        }
                    }
                    // Also check the continuations field as fallback
                    if continuationToken == nil {
                        continuationToken = playlistRenderer.continuations?.first?.nextContinuationData?.continuation
                    }
                }
            }

            // Second try: secondaryContents -> sectionListRenderer -> musicShelfRenderer or musicPlaylistShelfRenderer
            if songs.isEmpty,
               let secondarySections = twoColumn.secondaryContents?.sectionListRenderer?.contents {
                // Try musicShelfRenderer first
                if let shelfRenderer = secondarySections.first?.musicShelfRenderer {
                    if let shelfContents = shelfRenderer.contents {
                        for content in shelfContents {
                            if let item = content.musicResponsiveListItemRenderer,
                               let song = parseSearchItem(item) {
                                if case .song(let ytSong) = song {
                                    songs.append(ytSong)
                                }
                            }
                        }
                    }
                    continuationToken = shelfRenderer.continuations?.first?.nextContinuationData?.continuation
                }
                // Try musicPlaylistShelfRenderer
                else if let playlistRenderer = secondarySections.first?.musicPlaylistShelfRenderer {
                    if let playlistContents = playlistRenderer.contents {
                        for content in playlistContents {
                            // Check if this is a continuation item
                            if let continuationItem = content.continuationItemRenderer {
                                let token = continuationItem.continuationEndpoint?.continuationCommand?.token
                                if token != nil {
                                    continuationToken = token
                                }
                            }
                            // Otherwise parse as song
                            else if let item = content.musicResponsiveListItemRenderer,
                               let song = parseSearchItem(item) {
                                if case .song(let ytSong) = song {
                                    songs.append(ytSong)
                                }
                            }
                        }
                    }
                    // Also check the continuations field as fallback
                    if continuationToken == nil {
                        continuationToken = playlistRenderer.continuations?.first?.nextContinuationData?.continuation
                    }
                }
            }

            // Fetch remaining pages using continuation tokens
            while let token = continuationToken {
                let continuationResponse = try await client.makeContinuationRequest(
                    endpoint: "browse",
                    continuation: token,
                    responseType: BrowseResponse.self
                )

                // Parse continuation response (matching Android implementation)
                var continuationItems: [MusicPlaylistShelfRenderer.Content] = []

                // First try: sectionListContinuation
                if let sectionList = continuationResponse.continuationContents?.sectionListContinuation {
                    if let sections = sectionList.contents {
                        for section in sections {
                            if let contents = section.musicPlaylistShelfRenderer?.contents {
                                continuationItems.append(contentsOf: contents)
                            }
                        }
                    }
                }

                // Second try: onResponseReceivedActions (this is where continuation items actually are!)
                if let actions = continuationResponse.onResponseReceivedActions?.first?.appendContinuationItemsAction?.continuationItems {
                    continuationItems.append(contentsOf: actions)
                }

                if !continuationItems.isEmpty {
                    var nextToken: String? = nil
                    for item in continuationItems {
                        // Check if this is a continuation item
                        if let continuationItem = item.continuationItemRenderer {
                            nextToken = continuationItem.continuationEndpoint?.continuationCommand?.token
                        }
                        // Otherwise parse as song
                        else if let renderer = item.musicResponsiveListItemRenderer,
                           let song = parseSearchItem(renderer) {
                            if case .song(let ytSong) = song {
                                songs.append(ytSong)
                            }
                        }
                    }
                    continuationToken = nextToken
                } else {
                    // No more items
                    continuationToken = nil
                }
            }

            // Update playlist with actual song count
            let updatedPlaylist = YTPlaylist(
                id: playlist.id,
                name: playlist.name,
                author: playlist.author,
                thumbnailUrl: playlist.thumbnailUrl,
                songCount: songs.count,
                playlistId: playlist.playlistId
            )

            return (updatedPlaylist, songs)
        }

        // Try to get header from different renderer types (for other playlist types)
        var title: String = ""
        var thumbnailUrl: String? = nil

        if let editableHeader = response.header?.musicEditablePlaylistDetailHeaderRenderer?.header?.musicDetailHeaderRenderer {
            title = editableHeader.title?.combined ?? ""
            thumbnailUrl = editableHeader.thumbnail?.croppedSquareThumbnailRenderer?.thumbnail?.thumbnails?.last?.url
        } else if let detailHeader = response.header?.musicDetailHeaderRenderer {
            title = detailHeader.title?.combined ?? ""
            thumbnailUrl = detailHeader.thumbnail?.croppedSquareThumbnailRenderer?.thumbnail?.thumbnails?.last?.url
        } else if let immersiveHeader = response.header?.musicImmersiveHeaderRenderer {
            title = immersiveHeader.title?.combined ?? ""
            thumbnailUrl = immersiveHeader.thumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails?.last?.url
        } else if let visualHeader = response.header?.musicVisualHeaderRenderer {
            title = visualHeader.title?.combined ?? ""
            thumbnailUrl = visualHeader.foregroundThumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails?.last?.url
        } else {
            // TV shape no modelado (tu log: browseAuth VLLM OK via tv pero invalidResponse).
            // Fallback raw genérico antes de tirar.
            if client.isAuthenticated {
                do {
                    let raw = try await browseRawAuthenticated(browseId: browseId)
                    let rawList = rawSongs(raw)
                    await MainActor.run { DebugLogger.shared.log("📀 raw fallback \(browseId) songs=\(rawList.count)") }
                    if !rawList.isEmpty {
                        let pl = YTPlaylist(id: browseId, name: browseId, author: nil, thumbnailUrl: nil, songCount: rawList.count, playlistId: nil)
                        return (pl, rawList)
                    }
                } catch {
                    await MainActor.run { DebugLogger.shared.log("❌ raw fallback \(browseId) \(error)") }
                }
            }
            throw InnerTubeError.invalidResponse
        }

        let playlist = YTPlaylist(
            id: browseId,
            name: title,
            author: nil,
            thumbnailUrl: thumbnailUrl,
            songCount: 0,
            playlistId: nil  // This is from the browse endpoint, not a radio playlist
        )

        var songs: [YTSong] = []
        var continuationToken: String? = nil

        if let sections = response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents {
            for section in sections {
                if let shelf = section.musicPlaylistShelfRenderer {
                    if let shelfContents = shelf.contents {
                        for content in shelfContents {
                            if let contItem = content.continuationItemRenderer {
                                continuationToken = contItem.continuationEndpoint?.continuationCommand?.token ?? continuationToken
                            } else if let item = content.musicResponsiveListItemRenderer,
                               let song = parseSearchItem(item) {
                                if case .song(let ytSong) = song {
                                    songs.append(ytSong)
                                }
                            }
                        }
                    }
                    if continuationToken == nil {
                        continuationToken = shelf.continuations?.first?.nextContinuationData?.continuation
                    }
                }
            }
        }

        // Listas grandes (Top 100): página 1 trae token y pocos/sin items → seguir páginas.
        // Best-effort: ante error se conservan las canciones ya parseadas.
        while let token = continuationToken {
            do {
                let contResp: BrowseResponse = try await client.makeContinuationRequest(
                    endpoint: "browse", continuation: token, clientType: .webRemix,
                    forceNoAuth: !client.isAuthenticated, responseType: BrowseResponse.self
                )
                var items: [MusicPlaylistShelfRenderer.Content] = []
                if let sectionList = contResp.continuationContents?.sectionListContinuation,
                   let sections = sectionList.contents {
                    for section in sections {
                        if let contents = section.musicPlaylistShelfRenderer?.contents {
                            items.append(contentsOf: contents)
                        }
                    }
                }
                if let actions = contResp.onResponseReceivedActions?.first?.appendContinuationItemsAction?.continuationItems {
                    items.append(contentsOf: actions)
                }
                if items.isEmpty { continuationToken = nil; break }
                var nextToken: String? = nil
                for item in items {
                    if let contItem = item.continuationItemRenderer {
                        nextToken = contItem.continuationEndpoint?.continuationCommand?.token
                    } else if let renderer = item.musicResponsiveListItemRenderer,
                       let song = parseSearchItem(renderer), case .song(let ytSong) = song {
                        songs.append(ytSong)
                    }
                }
                continuationToken = nextToken
                await MainActor.run { DebugLogger.shared.log("📄 continuación \(browseId) songs=\(songs.count)") }
            } catch {
                await MainActor.run { DebugLogger.shared.log("⚠️ continuación \(browseId) fin/error: \(error)") }
                break
            }
        }

        // Ensure songs have thumbnail (use playlist thumbnail as fallback if needed)
        let playlistThumbnail = playlist.thumbnailUrl
        var songsWithThumbnails = songs.map { song in
            if song.thumbnailUrl != nil && !song.thumbnailUrl!.isEmpty {
                return song
            } else {
                return YTSong(
                    id: song.id,
                    title: song.title,
                    artists: song.artists,
                    duration: song.duration,
                    thumbnailUrl: playlistThumbnail,
                    albumId: song.albumId,
                    albumName: song.albumName
                )
            }
        }

        // Si tipado da 0 pero hay sesión (TV shape), prueba raw genérico (tu VLLM OK via tv → 0 songs).
        if songsWithThumbnails.isEmpty && client.isAuthenticated {
            do {
                let raw = try await browseRawAuthenticated(browseId: browseId)
                let rawList = rawSongs(raw)
                await MainActor.run { DebugLogger.shared.log("📀 raw fallback2 \(browseId) songs=\(rawList.count)") }
                if !rawList.isEmpty {
                    songsWithThumbnails = rawList.map { s in
                        YTSong(id: s.id, title: s.title, artists: s.artists, duration: s.duration, thumbnailUrl: s.thumbnailUrl ?? playlistThumbnail, albumId: s.albumId, albumName: s.albumName)
                    }
                }
            } catch {
                await MainActor.run { DebugLogger.shared.log("❌ raw fallback2 \(browseId) \(error)") }
            }
        }

        // IDs públicos con sesión Bearer: el raw autenticado falla (400s) y la lista
        // quedaría gris/vacía. Último recurso: raw PÚBLICO sin auth.
        if songsWithThumbnails.isEmpty {
            let isPrivateId = browseId == "VLLM" || browseId.hasPrefix("FEmusic_")
            if !isPrivateId {
                do {
                    let raw = try await client.makeRawRequest(
                        endpoint: "browse", body: ["browseId": browseId],
                        clientType: .webRemix, forceNoAuth: true
                    )
                    let rawList = rawSongs(raw)
                    await MainActor.run { DebugLogger.shared.log("📀 raw fallback3 público \(browseId) songs=\(rawList.count)") }
                    if !rawList.isEmpty {
                        songsWithThumbnails = rawList.map { s in
                            YTSong(id: s.id, title: s.title, artists: s.artists, duration: s.duration, thumbnailUrl: s.thumbnailUrl ?? playlistThumbnail, albumId: s.albumId, albumName: s.albumName)
                        }
                    }
                } catch {
                    await MainActor.run { DebugLogger.shared.log("❌ raw fallback3 \(browseId) \(error)") }
                }
            }
        }

        return (playlist, songsWithThumbnails)
    }

    // MARK: - Home Feed

    func getHome(params: String? = nil, continuation: String? = nil) async throws -> HomePage {
        let response: BrowseResponse

        if let continuation = continuation {
            // Handle continuation (infinite scroll)
            response = try await client.makeContinuationRequest(
                endpoint: "browse",
                continuation: continuation,
                responseType: BrowseResponse.self
            )
            return parseHomeContinuation(response)
        } else {
            // Initial home page load with optional params for chip filtering
            response = try await browseWithParams(browseId: "FEmusic_home", params: params)
        }

        return parseHomePage(response)
    }

    /// Browse with optional params support (contenido público: noAuth primero si hay Bearer)
    func browseWithParams(browseId: String, params: String? = nil) async throws -> BrowseResponse {
        var body: [String: Any] = [
            "browseId": browseId
        ]

        if let params = params {
            body["params"] = params
        }

        let hasBearer = OAuthManager.bearerHeaderSync != nil
        let attempts: [(InnerTubeClientType, Bool)] = client.isAuthenticated
            ? (hasBearer
                ? [(.webRemix, true), (.ios, true), (.android, true), (.ios, false), (.webRemix, false)]
                : [(.webRemix, false), (.ios, false), (.webRemix, true), (.ios, true)])
            : [(.webRemix, false)]
        var lastErr: Error = InnerTubeError.authenticationExpired
        for (ctype, noAuth) in attempts {
            do {
                if Task.isCancelled { throw CancellationError() }
                return try await client.makeRequest(
                    endpoint: "browse",
                    body: body,
                    clientType: ctype,
                    forceNoAuth: noAuth,
                    responseType: BrowseResponse.self
                )
            } catch let e as URLError where e.code == .cancelled {
                throw e
            } catch {
                if (error as NSError).code == -999 { throw error }
                lastErr = error
                continue
            }
        }
        throw lastErr
    }

    // MARK: - Explore Page

    func getExplore() async throws -> ExplorePage {
        let response = try await browse(browseId: "FEmusic_explore")
        return parseExplorePage(response)
    }

    private func parseExplorePage(_ response: BrowseResponse) -> ExplorePage {
        guard let sectionContents = response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents else {
            return ExplorePage(newReleaseAlbums: [], moodAndGenres: [])
        }

        var newReleaseAlbums: [YTAlbum] = []
        var moodAndGenres: [MoodAndGenre] = []

        for section in sectionContents {
            if let carouselShelf = section.musicCarouselShelfRenderer {
                let browseId = carouselShelf.header?.musicCarouselShelfBasicHeaderRenderer?.moreContentButton?.buttonRenderer?.navigationEndpoint?.browseEndpoint?.browseId

                // Check if this is the new releases section
                if browseId == "FEmusic_new_releases_albums" {
                    if let contents = carouselShelf.contents {
                        for content in contents {
                            if let itemRenderer = content.musicTwoRowItemRenderer,
                               let item = parseHomeItem(itemRenderer),
                               case .album(let album) = item {
                                newReleaseAlbums.append(album)
                            }
                        }
                    }
                }

                // Check if this is mood and genres section
                if browseId == "FEmusic_moods_and_genres" {
                    if let contents = carouselShelf.contents {
                        for content in contents {
                            if let navButton = content.musicNavigationButtonRenderer {
                                let title = navButton.buttonText?.combined ?? ""
                                let params = navButton.clickCommand?.browseEndpoint?.params
                                let navBrowseId = navButton.clickCommand?.browseEndpoint?.browseId

                                moodAndGenres.append(MoodAndGenre(
                                    id: navBrowseId ?? UUID().uuidString,
                                    title: title,
                                    params: params,
                                    color: nil
                                ))
                            }
                        }
                    }
                }
            }
        }

        return ExplorePage(newReleaseAlbums: newReleaseAlbums, moodAndGenres: moodAndGenres)
    }

    // MARK: - Mood and Genres Browse

    func getMoodAndGenres() async throws -> [MoodAndGenre] {
        let response = try await browse(browseId: "FEmusic_moods_and_genres")
        return parseMoodAndGenres(response)
    }

    private func parseMoodAndGenres(_ response: BrowseResponse) -> [MoodAndGenre] {
        guard let sectionContents = response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents else {
            return []
        }

        var genres: [MoodAndGenre] = []

        for section in sectionContents {
            if let gridRenderer = section.gridRenderer {
                if let items = gridRenderer.items {
                    for item in items {
                        if let navButton = item.musicNavigationButtonRenderer {
                            let title = navButton.buttonText?.combined ?? ""
                            let browseId = navButton.clickCommand?.browseEndpoint?.browseId
                            let params = navButton.clickCommand?.browseEndpoint?.params

                            genres.append(MoodAndGenre(
                                id: browseId ?? UUID().uuidString,
                                title: title,
                                params: params,
                                color: nil
                            ))
                        }
                    }
                }
            }
        }

        return genres
    }

    // MARK: - Artist Page

    func getArtist(browseId: String) async throws -> ArtistPage {
        let response: BrowseResponse
        if client.isAuthenticated {
            do {
                response = try await browseAuthenticated(browseId: browseId)
            } catch {
                response = try await browse(browseId: browseId)
            }
        } else {
            response = try await browse(browseId: browseId)
        }
        let page = parseArtistPage(response, browseId: browseId)
        if !page.sections.isEmpty {
            return page
        }

        // Raw fallback if structured response didn't yield sections
        do {
            let raw: [String: Any]
            if client.isAuthenticated {
                do {
                    raw = try await browseRawAuthenticated(browseId: browseId)
                } catch {
                    raw = try await browseRawPublic(browseId: browseId)
                }
            } else {
                raw = try await browseRawPublic(browseId: browseId)
            }
            let rawLists = rawPlaylists(raw)
            let rawSongList = rawSongs(raw)
            var items: [HomeItem] = []
            for s in rawSongList {
                items.append(.song(s))
            }
            for pl in rawLists {
                items.append(.playlist(pl))
            }
            if !items.isEmpty {
                await MainActor.run { DebugLogger.shared.log("📀 raw fallback artist \(browseId) items=\(items.count)") }
                let section = ArtistSection(title: "Top Songs & Albums", items: items, browseId: nil)
                return ArtistPage(artist: page.artist, sections: [section], description: nil)
            }
        } catch {}

        return page
    }

    private func parseArtistPage(_ response: BrowseResponse, browseId: String) -> ArtistPage {
        // Extract artist info from header
        var artistName = ""
        var thumbnailUrl: String?
        var description: String?

        // Try musicDetailHeaderRenderer (common for artists)
        if let header = response.header?.musicDetailHeaderRenderer {
            artistName = header.title?.combined ?? ""
            thumbnailUrl = header.thumbnail?.croppedSquareThumbnailRenderer?.thumbnail?.thumbnails?.last?.url
        }

        let artist = YTArtist(id: browseId, name: artistName, thumbnailUrl: thumbnailUrl)

        // Parse sections
        var sections: [ArtistSection] = []

        if let sectionContents = response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents {
            for sectionContent in sectionContents {
                if let carouselShelf = sectionContent.musicCarouselShelfRenderer {
                    if let section = parseArtistSection(carouselShelf) {
                        sections.append(section)
                    }
                }
            }
        }

        return ArtistPage(artist: artist, sections: sections, description: description)
    }

    private func parseArtistSection(_ shelf: MusicCarouselShelfRenderer) -> ArtistSection? {
        guard let header = shelf.header?.musicCarouselShelfBasicHeaderRenderer,
              let title = header.title?.combined else {
            return nil
        }

        let browseId = header.moreContentButton?.buttonRenderer?.navigationEndpoint?.browseEndpoint?.browseId

        var items: [HomeItem] = []
        if let contents = shelf.contents {
            for content in contents {
                if let itemRenderer = content.musicTwoRowItemRenderer,
                   let item = parseHomeItem(itemRenderer) {
                    items.append(item)
                }
            }
        }

        guard !items.isEmpty else { return nil }

        return ArtistSection(title: title, items: items, browseId: browseId)
    }

    // MARK: - Browse Page (Generic)

    func browsePage(browseId: String, params: String? = nil) async throws -> BrowseResult {
        let response = try await browseWithParams(browseId: browseId, params: params)
        return parseBrowsePage(response)
    }

    private func parseBrowsePage(_ response: BrowseResponse) -> BrowseResult {
        var title: String?
        var sections: [BrowseSection] = []

        // Try to get title from header
        if let header = response.header?.musicDetailHeaderRenderer {
            title = header.title?.combined
        }

        // Parse sections
        if let sectionContents = response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents {
            for sectionContent in sectionContents {
                // Carousel shelf
                if let carouselShelf = sectionContent.musicCarouselShelfRenderer {
                    if let section = parseBrowseCarouselSection(carouselShelf) {
                        sections.append(section)
                    }
                }
                // Grid renderer
                else if let gridRenderer = sectionContent.gridRenderer {
                    if let section = parseBrowseGridSection(gridRenderer) {
                        sections.append(section)
                    }
                }
            }
        }

        return BrowseResult(title: title, sections: sections)
    }

    private func parseBrowseCarouselSection(_ shelf: MusicCarouselShelfRenderer) -> BrowseSection? {
        let title = shelf.header?.musicCarouselShelfBasicHeaderRenderer?.title?.combined

        var items: [HomeItem] = []
        if let contents = shelf.contents {
            for content in contents {
                if let itemRenderer = content.musicTwoRowItemRenderer,
                   let item = parseHomeItem(itemRenderer) {
                    items.append(item)
                }
            }
        }

        guard !items.isEmpty else { return nil }

        return BrowseSection(title: title, items: items)
    }

    private func parseBrowseGridSection(_ grid: GridRenderer) -> BrowseSection? {
        let title = grid.header?.gridHeaderRenderer?.title?.combined

        var items: [HomeItem] = []
        if let gridItems = grid.items {
            for item in gridItems {
                if let itemRenderer = item.musicTwoRowItemRenderer,
                   let homeItem = parseHomeItem(itemRenderer) {
                    items.append(homeItem)
                }
            }
        }

        guard !items.isEmpty else { return nil }

        return BrowseSection(title: title, items: items)
    }

    private func parseHomePage(_ response: BrowseResponse) -> HomePage {
        guard let sectionListRenderer = response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer else {
            return HomePage(chips: [], sections: [], continuation: nil)
        }

        // Parse chips (filter categories)
        var chips: [HomeChip] = []
        if let chipRenderers = sectionListRenderer.header?.chipCloudRenderer?.chips {
            chips = chipRenderers.compactMap { chip in
                guard let renderer = chip.chipCloudChipRenderer,
                      let text = renderer.text?.combined else {
                    return nil
                }

                let params = renderer.navigationEndpoint?.browseEndpoint?.browseId
                let isSelected = renderer.isSelected ?? false

                return HomeChip(title: text, params: params, isSelected: isSelected)
            }
        }

        // Parse sections
        var sections: [HomeSection] = []
        if let sectionContents = sectionListRenderer.contents {
            for sectionContent in sectionContents {
                if let carouselShelf = sectionContent.musicCarouselShelfRenderer {
                    if let section = parseHomeSection(carouselShelf) {
                        sections.append(section)
                    }
                }
            }
        }

        // Parse continuation token
        let continuation = sectionListRenderer.continuations?.first?.nextContinuationData?.continuation

        return HomePage(chips: chips, sections: sections, continuation: continuation)
    }

    private func parseHomeSection(_ shelf: MusicCarouselShelfRenderer) -> HomeSection? {
        guard let header = shelf.header?.musicCarouselShelfBasicHeaderRenderer,
              let title = header.title?.combined else {
            return nil
        }

        let label = header.strapline?.combined
        let browseId = header.moreContentButton?.buttonRenderer?.navigationEndpoint?.browseEndpoint?.browseId
        let thumbnail = header.thumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails?.last?.url

        // Parse items
        var items: [HomeItem] = []
        if let contents = shelf.contents {
            for content in contents {
                if let itemRenderer = content.musicTwoRowItemRenderer,
                   let item = parseHomeItem(itemRenderer) {
                    items.append(item)
                }
            }
        }

        guard !items.isEmpty else { return nil }

        return HomeSection(title: title, label: label, thumbnail: thumbnail, items: items, browseId: browseId)
    }

    private func parseHomeContinuation(_ response: BrowseResponse) -> HomePage {
        // Parse continuation response (no header/chips, just sections)
        var sections: [HomeSection] = []

        if let sectionContents = response.continuationContents?.sectionListContinuation?.contents {
            for sectionContent in sectionContents {
                if let carouselShelf = sectionContent.musicCarouselShelfRenderer {
                    if let section = parseHomeSection(carouselShelf) {
                        sections.append(section)
                    }
                }
            }
        }

        // Parse continuation token
        let continuation = response.continuationContents?.sectionListContinuation?.continuations?.first?.nextContinuationData?.continuation

        return HomePage(chips: [], sections: sections, continuation: continuation)
    }

    private func parseHomeItem(_ item: MusicCarouselShelfRenderer.Content.MusicTwoRowItemRenderer) -> HomeItem? {
        // Determine item type based on navigationEndpoint structure
        let isSong = item.navigationEndpoint?.watchEndpoint != nil

        let isPlaylist = item.navigationEndpoint?.browseEndpoint?.browseEndpointContextSupportedConfigs?
            .browseEndpointContextMusicConfig?.pageType == "MUSIC_PAGE_TYPE_PLAYLIST"

        let isAlbum = item.navigationEndpoint?.browseEndpoint?.browseEndpointContextSupportedConfigs?
            .browseEndpointContextMusicConfig?.pageType == "MUSIC_PAGE_TYPE_ALBUM" ||
            item.navigationEndpoint?.browseEndpoint?.browseEndpointContextSupportedConfigs?
            .browseEndpointContextMusicConfig?.pageType == "MUSIC_PAGE_TYPE_AUDIOBOOK"

        let isArtist = item.navigationEndpoint?.browseEndpoint?.browseEndpointContextSupportedConfigs?
            .browseEndpointContextMusicConfig?.pageType == "MUSIC_PAGE_TYPE_ARTIST" ||
            item.navigationEndpoint?.browseEndpoint?.browseEndpointContextSupportedConfigs?
            .browseEndpointContextMusicConfig?.pageType == "MUSIC_PAGE_TYPE_LIBRARY_ARTIST"

        let thumbnailUrl = item.thumbnailRenderer?.musicThumbnailRenderer?.thumbnail?.thumbnails?.last?.url

        let title = item.title?.combined ?? ""
        let subtitle = item.subtitle?.combined ?? ""

        if isSong {
            guard let videoId = item.navigationEndpoint?.watchEndpoint?.videoId else {
                return nil
            }

            return .song(YTSong(
                id: videoId,
                title: title,
                artists: subtitle,
                duration: nil,
                thumbnailUrl: thumbnailUrl,
                albumId: nil,
                albumName: nil
            ))
        } else if isArtist {
            guard let browseId = item.navigationEndpoint?.browseEndpoint?.browseId else {
                return nil
            }

            return .artist(YTArtist(
                id: browseId,
                name: title,
                thumbnailUrl: thumbnailUrl
            ))
        } else if isAlbum {
            guard let browseId = item.navigationEndpoint?.browseEndpoint?.browseId else {
                return nil
            }

            return .album(YTAlbum(
                id: browseId,
                title: title,
                artists: subtitle,
                year: nil,
                thumbnailUrl: thumbnailUrl
            ))
        } else if isPlaylist {
            guard let browseId = item.navigationEndpoint?.browseEndpoint?.browseId else {
                return nil
            }

            let id = stripVL(browseId)

            // Extract playlistId from play button for radio playlists
            let playlistId = item.thumbnailOverlay?.musicItemThumbnailOverlayRenderer?.content?
                .musicPlayButtonRenderer?.playNavigationEndpoint?.watchPlaylistEndpoint?.playlistId

            return .playlist(YTPlaylist(
                id: id,
                name: title,
                author: subtitle,
                thumbnailUrl: thumbnailUrl,
                songCount: 0,
                playlistId: playlistId
            ))
        }

        return nil
    }

    // MARK: - Radio Playlist

    func getRadioPlaylist(playlistId: String) async throws -> [YTSong] {
        // For radio playlists, we need to call the next endpoint
        // We use a dummy videoId - the first video from the playlist will be used
        let response = try await getNext(videoId: "dQw4w9WgXcQ", playlistId: playlistId)

        // Parse songs from the playlist panel
        guard let contents = response.contents?.singleColumnMusicWatchNextResultsRenderer?
            .tabbedRenderer?.watchNextTabbedResultsRenderer?.tabs?.first?.tabRenderer?
            .content?.musicQueueRenderer?.content?.playlistPanelRenderer?.contents else {
            return []
        }

        var songs: [YTSong] = []
        for item in contents {
            if let renderer = item.playlistPanelVideoRenderer,
               let videoId = renderer.videoId,
               let title = renderer.title?.combined {

                let artists = renderer.longBylineText?.combined ?? ""

                songs.append(YTSong(
                    id: videoId,
                    title: title,
                    artists: artists,
                    duration: nil,
                    thumbnailUrl: renderer.thumbnail?.thumbnails?.last?.url,
                    albumId: nil,
                    albumName: nil
                ))
            }
        }

        return songs
    }

    // MARK: - Next (Queue/Radio)

    func getNext(videoId: String, playlistId: String? = nil, continuation: String? = nil) async throws -> NextResponse {
        var body: [String: Any] = [
            "videoId": videoId,
            "enablePersistentPlaylistPanel": true
        ]

        if let playlistId = playlistId {
            body["playlistId"] = playlistId
        }

        if let continuation = continuation {
            body["continuation"] = continuation
        }

        // webRemix+Bearer da 400; el cliente TV es el único que acepta Bearer
        let ctype: InnerTubeClientType = client.hasBearer ? .tv : .webRemix
        do {
            let resp: NextResponse = try await client.makeRequest(
                endpoint: "next",
                body: body,
                clientType: ctype,
                responseType: NextResponse.self
            )
            return resp
        } catch {
            // Cancelación de SwiftUI (.task re-ejecutado): no hacer fallback, solo propagar
            if error is CancellationError || (error as NSError).code == -999
                || (error as? URLError)?.code == .cancelled { throw error }
            await MainActor.run { DebugLogger.shared.log("❌ next via \(ctype) err=\(error)") }
            // Fallback público sin auth (radio de contenido público no necesita login)
            if client.hasBearer {
                do {
                    let resp: NextResponse = try await client.makeRequest(
                        endpoint: "next",
                        body: body,
                        clientType: .webRemix,
                        forceNoAuth: true,
                        responseType: NextResponse.self
                    )
                    return resp
                } catch {
                    await MainActor.run { DebugLogger.shared.log("❌ next fallback noAuth err=\(error)") }
                    throw error
                }
            }
            throw error
        }
    }

    // Get a radio queue (auto-mix) for a song - returns songs and continuation token
    func getRadioQueue(videoId: String, continuation: String? = nil) async throws -> (songs: [YTSong], continuation: String?) {
        // For radio, use RDAMVM prefix which creates an automix
        let playlistId = "RDAMVM\(videoId)"
        let response = try await getNext(videoId: videoId, playlistId: playlistId, continuation: continuation)

        // Parse songs from the playlist panel
        guard let contents = response.contents?.singleColumnMusicWatchNextResultsRenderer?
            .tabbedRenderer?.watchNextTabbedResultsRenderer?.tabs?.first?.tabRenderer?
            .content?.musicQueueRenderer?.content?.playlistPanelRenderer?.contents else {
            return ([], nil)
        }

        var songs: [YTSong] = []
        for item in contents {
            if let renderer = item.playlistPanelVideoRenderer,
               let videoId = renderer.videoId,
               let title = renderer.title?.combined {

                let artists = renderer.longBylineText?.combined ?? ""

                songs.append(YTSong(
                    id: videoId,
                    title: title,
                    artists: artists,
                    duration: nil,
                    thumbnailUrl: renderer.thumbnail?.thumbnails?.last?.url,
                    albumId: nil,
                    albumName: nil
                ))
            }
        }

        // Extract continuation token for infinite scrolling
        let continuationToken = response.contents?.singleColumnMusicWatchNextResultsRenderer?
            .tabbedRenderer?.watchNextTabbedResultsRenderer?.tabs?.first?.tabRenderer?
            .content?.musicQueueRenderer?.content?.playlistPanelRenderer?.continuations?.first?
            .nextContinuationData?.continuation

        return (songs, continuationToken)
    }

    // MARK: - Library (Authenticated)

    func getLikedSongs() async throws -> [YTSong] {
        guard client.isAuthenticated else {
            throw InnerTubeError.notAuthenticated
        }

        // "VLLM" is the browse ID for the "Liked Music" playlist
        // Matching Android's YouTube.playlist("LM")
        print("🎵 [YouTube API] Fetching liked songs from playlist VLLM...")
        let (_, songs) = try await getPlaylist(browseId: "VLLM")
        print("✅ [YouTube API] Retrieved \(songs.count) liked songs")
        return songs
    }

    func getLibraryPlaylists() async throws -> [YTPlaylist] {
        guard client.isAuthenticated else {
            throw InnerTubeError.notAuthenticated
        }

        await MainActor.run { DebugLogger.shared.log("📚 getLibraryPlaylists isAuth=\(client.isAuthenticated) \(client.debugAuthState)") }
        let response: BrowseResponse
        do {
            // Librería privada: SIN fallback público (si no, devuelve 0 listas vacías)
            response = try await browseAuthenticated(browseId: "FEmusic_liked_playlists")
            await MainActor.run { DebugLogger.shared.log("📚 browse FEmusic_liked_playlists OK") }
        } catch {
            await MainActor.run { DebugLogger.shared.log("❌ browse FEmusic_liked_playlists \(error) \(client.debugAuthState)") }
            throw error
        }

        var playlists: [YTPlaylist] = []
        await MainActor.run { DebugLogger.shared.log("📚 parse playlists sections=\(response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents?.count ?? -1)") }

        if let tabs = response.contents?.singleColumnBrowseResultsRenderer?.tabs,
           let firstTab = tabs.first,
           let sectionContents = firstTab.tabRenderer?.content?.sectionListRenderer?.contents {
            await MainActor.run { DebugLogger.shared.log("📚 sections \(sectionContents.count) firstTypes=\(sectionContents.prefix(2).map { String(describing: type(of: $0)) })") }
            for (idx, section) in sectionContents.enumerated() {
                await MainActor.run { DebugLogger.shared.log("📚 sec \(idx) hasGrid=\(section.gridRenderer != nil) hasShelf=\(section.musicShelfRenderer != nil) hasCarousel=\(section.musicCarouselShelfRenderer != nil) hasItemSec=\(section.itemSectionRenderer != nil)") }
                // Check for authentication error message
                if let itemSection = section.itemSectionRenderer,
                   let firstContent = itemSection.contents?.first,
                   let messageRenderer = firstContent.messageRenderer {
                    let messageText = messageRenderer.text?.combined ?? ""

                    if messageRenderer.button?.buttonRenderer?.navigationEndpoint?.signInEndpoint != nil {
                        if messageText.contains("Looking for what you've liked") {
                            throw InnerTubeError.invalidResponse  // Different error for account not set up
                        } else {
                            throw InnerTubeError.authenticationExpired
                        }
                    }
                }

                // Try gridRenderer
                if let gridItems = section.gridRenderer?.items {
                    for item in gridItems {
                        if let renderer = item.musicTwoRowItemRenderer,
                           let browseId = renderer.navigationEndpoint?.browseEndpoint?.browseId,
                           let title = renderer.title?.combined {

                            let subtitle = renderer.subtitle?.combined
                            let thumbnailUrl = renderer.thumbnailRenderer?.musicThumbnailRenderer?.thumbnail?.thumbnails?.last?.url

                            // Extract song count from subtitle (usually in format "Creator • X songs")
                            let songCount = parseSongCount(from: subtitle)

                            // Strip VL prefix if present
                            let playlistId = browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId

                            playlists.append(YTPlaylist(
                                id: playlistId,
                                name: title,
                                author: nil,
                                thumbnailUrl: thumbnailUrl,
                                songCount: songCount,
                                playlistId: nil
                            ))
                        }
                    }
                }

                // Try musicShelfRenderer (alternative structure)
                if let shelfItems = section.musicShelfRenderer?.contents {
                    for item in shelfItems {
                        if let renderer = item.musicResponsiveListItemRenderer,
                           let browseId = renderer.navigationEndpoint?.browseEndpoint?.browseId,
                           let flexColumns = renderer.flexColumns,
                           let title = flexColumns.first?.musicResponsiveListItemFlexColumnRenderer?.text?.combined {

                            let thumbnailUrl = renderer.thumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails?.last?.url

                            // Try to get song count from second flex column
                            let subtitle = flexColumns.count > 1 ? flexColumns[1].musicResponsiveListItemFlexColumnRenderer?.text?.combined : nil
                            let songCount = parseSongCount(from: subtitle)

                            // Strip VL prefix if present
                            let playlistId = browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId

                            playlists.append(YTPlaylist(
                                id: playlistId,
                                name: title,
                                author: nil,
                                thumbnailUrl: thumbnailUrl,
                                songCount: songCount,
                                playlistId: nil
                            ))
                        }
                    }
                }

                // Try musicCarouselShelfRenderer (para cuentas con 1 sola playlist creada, a veces viene como carrusel)
                if let carousel = section.musicCarouselShelfRenderer, let contents = carousel.contents {
                    for content in contents {
                        if let renderer = content.musicTwoRowItemRenderer,
                           let browseId = renderer.navigationEndpoint?.browseEndpoint?.browseId,
                           let title = renderer.title?.combined {
                            let subtitle = renderer.subtitle?.combined
                            let thumbnailUrl = renderer.thumbnailRenderer?.musicThumbnailRenderer?.thumbnail?.thumbnails?.last?.url
                            let songCount = parseSongCount(from: subtitle)
                            let playlistId = browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId
                            // Evita duplicados
                            if !playlists.contains(where: { $0.id == playlistId }) {
                                playlists.append(YTPlaylist(id: playlistId, name: title, author: nil, thumbnailUrl: thumbnailUrl, songCount: songCount, playlistId: nil))
                            }
                        }
                    }
                }
            }
        }

        await MainActor.run { DebugLogger.shared.log("📚 parsed \(playlists.count) playlists (tipado)") }
        if !playlists.isEmpty { return playlists }
        // Fallback raw: TV devuelve 200 pero con shape no modelado → contents nil → 0 listas.
        // Tu log: browseAuth FEmusic_liked_playlists OK via tv pero parsed 0.
        do {
            let raw = try await browseRawAuthenticated(browseId: "FEmusic_liked_playlists")
            var merged = rawPlaylists(raw)
            // Tiles de la tab Playlists (ids VL/PL con título propio): fusionar sin duplicar
            let tiles = await rawTvTabTiles(raw, tabIds: ["FEmusic_liked_playlists"], titleHints: ["playlist"])
            for t in tiles {
                guard let bid = t.browseId, (bid.hasPrefix("VL") || bid.hasPrefix("PL")) else { continue }
                let pid = bid.hasPrefix("VL") ? stripVL(bid) : bid
                if !merged.contains(where: { $0.id == pid }) {
                    merged.append(YTPlaylist(id: pid, name: t.title, author: t.subtitle.isEmpty ? nil : t.subtitle, thumbnailUrl: t.thumb, songCount: 0, playlistId: nil))
                }
            }
            await MainActor.run { DebugLogger.shared.log("📚 raw parsed \(merged.count) playlists names=\(merged.prefix(8).map { $0.name })") }
            if !merged.isEmpty { return merged }
        } catch {
            await MainActor.run { DebugLogger.shared.log("❌ raw FEmusic_liked_playlists \(error)") }
        }
        return playlists
    }

    func getLibraryAlbums() async throws -> [YTAlbum] {
        guard client.isAuthenticated else {
            throw InnerTubeError.notAuthenticated
        }

        do {
            let raw = try await browseRawAuthenticated(browseId: "FEmusic_liked_albums")
            var albums = rawAlbums(raw)
            // Tiles de la tab Albums (MPRE o sin endpoint): la forma real de la librería TV
            let tiles = await rawTvTabTiles(raw, tabIds: ["FEmusic_liked_albums"], titleHints: ["album"])
            for t in tiles {
                if let bid = t.browseId, bid.hasPrefix("MPRE"), !albums.contains(where: { $0.id == bid }) {
                    albums.append(YTAlbum(id: bid, title: t.title, artists: t.subtitle, year: nil, thumbnailUrl: t.thumb))
                } else if t.browseId == nil && t.watchVideoId == nil {
                    let aid = t.contentId ?? t.title
                    if !aid.isEmpty && !albums.contains(where: { $0.id == aid }) {
                        albums.append(YTAlbum(id: aid, title: t.title, artists: t.subtitle, year: nil, thumbnailUrl: t.thumb))
                    }
                }
            }
            await MainActor.run { DebugLogger.shared.log("📀 getLibraryAlbums rawAlbums=\(albums.count) names=\(albums.prefix(8).map { $0.title })") }
            return albums
        } catch {
            return []
        }
    }

    func getLibraryArtists() async throws -> [YTArtist] {
        guard client.isAuthenticated else {
            throw InnerTubeError.notAuthenticated
        }

        do {
            let raw = try await browseRawAuthenticated(browseId: "FEmusic_library_corpus_artists")
            var artists = rawArtists(raw)
            // Tiles de la tab Artists/Subscriptions (UC o sin endpoint)
            let tiles = await rawTvTabTiles(raw, tabIds: ["FEmusic_library_corpus_artists"], titleHints: ["artist", "subscription"])
            for t in tiles {
                if let bid = t.browseId, bid.hasPrefix("UC"), !artists.contains(where: { $0.id == bid }) {
                    artists.append(YTArtist(id: bid, name: t.title, thumbnailUrl: t.thumb))
                } else if t.browseId == nil && t.watchVideoId == nil {
                    let aid = t.contentId ?? t.title
                    if !aid.isEmpty && !artists.contains(where: { $0.id == aid }) {
                        artists.append(YTArtist(id: aid, name: t.title, thumbnailUrl: t.thumb))
                    }
                }
            }
            await MainActor.run { DebugLogger.shared.log("📀 getLibraryArtists rawArtists=\(artists.count) names=\(artists.prefix(8).map { $0.name })") }
            return artists
        } catch {
            return []
        }
    }

    private func parseSongCount(from subtitle: String?) -> Int {
        guard let subtitle = subtitle else { return 0 }

        // Format: "Creator • 50 songs" or "Creator • 335 tracks"
        // Split by bullet character and get the part after it
        if let afterBullet = subtitle.components(separatedBy: "•").last?.trimmingCharacters(in: .whitespaces) {
            // Now extract the number from "50 songs" or "335 tracks"
            let components = afterBullet.components(separatedBy: " ")
            if let first = components.first, let count = Int(first) {
                return count
            }
        }

        return 0
    }

    // MARK: - Actions (Like, Subscribe, etc.)

    func likeSong(videoId: String) async throws {
        guard client.isAuthenticated else {
            throw InnerTubeError.notAuthenticated
        }

        let body: [String: Any] = [
            "target": ["videoId": videoId]
        ]

        let _: EmptyResponse = try await client.makeRequest(
            endpoint: "like/like",
            body: body,
            responseType: EmptyResponse.self
        )
    }

    func unlikeSong(videoId: String) async throws {
        guard client.isAuthenticated else {
            throw InnerTubeError.notAuthenticated
        }

        let body: [String: Any] = [
            "target": ["videoId": videoId]
        ]

        let _: EmptyResponse = try await client.makeRequest(
            endpoint: "like/removelike",
            body: body,
            responseType: EmptyResponse.self
        )
    }

    // MARK: - Music History

    func getMusicHistory() async throws -> [HistorySection] {
        guard client.isAuthenticated else {
            throw InnerTubeError.notAuthenticated
        }

        let response = try await browseAuthenticated(browseId: "FEmusic_history")
        return parseHistoryPage(response)
    }

    private func parseHistoryPage(_ response: BrowseResponse) -> [HistorySection] {
        guard let sectionContents = response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents else {
            return []
        }

        var sections: [HistorySection] = []

        for sectionContent in sectionContents {
            if let musicShelf = sectionContent.musicShelfRenderer {
                let title = musicShelf.title?.combined ?? "Recent"
                var songs: [YTSong] = []

                if let contents = musicShelf.contents {
                    for content in contents {
                        if let item = content.musicResponsiveListItemRenderer,
                           let result = parseSearchItem(item),
                           case .song(let song) = result {
                            songs.append(song)
                        }
                    }
                }

                if !songs.isEmpty {
                    sections.append(HistorySection(title: title, songs: songs))
                }
            }
        }

        return sections
    }

    // MARK: - Charts

    func getCharts() async throws -> ChartsPage {
        let response = try await browseWithParams(browseId: "FEmusic_charts", params: "ggMGCgQIgAQ%3D")
        let page = parseChartsPage(response)
        if !page.sections.isEmpty { return page }
        // La vista Charts muestra BLANCO sin error cuando sections=[]: la forma del
        // response cambió. Fallback con parseo genérico del JSON crudo.
        do {
            let raw = try await client.makeRawRequest(
                endpoint: "browse",
                body: ["browseId": "FEmusic_charts", "params": "ggMGCgQIgAQ%3D"],
                clientType: .webRemix,
                forceNoAuth: !client.isAuthenticated
            )
            let sections = rawChartSections(raw)
            await MainActor.run { DebugLogger.shared.log("📊 charts raw fallback sections=\(sections.count)") }
            if !sections.isEmpty { return ChartsPage(sections: sections) }
            let keys = Self.deepKeys(raw, depth: 6)
            await MainActor.run { DebugLogger.shared.log("🔍 charts deepKeys=\(keys.prefix(40))") }
        } catch {
            await MainActor.run { DebugLogger.shared.log("❌ charts raw fallback \(error)") }
        }
        return page
    }

    private func parseChartsPage(_ response: BrowseResponse) -> ChartsPage {
        guard let sectionContents = response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents else {
            return ChartsPage(sections: [])
        }

        var sections: [ChartSection] = []

        for sectionContent in sectionContents {
            // musicShelfRenderer (Top songs): items directos
            if let shelf = sectionContent.musicShelfRenderer,
               let shelfContents = shelf.contents {
                var items: [HomeItem] = []
                for wrapper in shelfContents {
                    if let item = wrapper.musicResponsiveListItemRenderer,
                       let result = parseSearchItem(item) {
                        items.append(homeItem(from: result))
                    }
                }
                if !items.isEmpty {
                    let title = shelf.title?.combined ?? "Top songs"
                    sections.append(ChartSection(title: title, items: items))
                }
            }
            if let carouselShelf = sectionContent.musicCarouselShelfRenderer {
                let title = carouselShelf.header?.musicCarouselShelfBasicHeaderRenderer?.title?.combined ?? ""
                var items: [HomeItem] = []

                if let contents = carouselShelf.contents {
                    for content in contents {
                        if let itemRenderer = content.musicTwoRowItemRenderer,
                           let item = parseHomeItem(itemRenderer) {
                            items.append(item)
                        } else if let listItem = content.musicResponsiveListItemRenderer,
                           let result = parseSearchItem(listItem) {
                            // Top artists: listItems dentro del carousel
                            items.append(homeItem(from: result))
                        }
                    }
                }

                if !items.isEmpty {
                    sections.append(ChartSection(title: title, items: items))
                }
            }
        }

        return ChartsPage(sections: sections)
    }

    private func homeItem(from result: SearchResult) -> HomeItem {
        switch result {
        case .song(let s): return .song(s)
        case .album(let a): return .album(a)
        case .artist(let a): return .artist(a)
        case .playlist(let p): return .playlist(p)
        }
    }

    /// Quita el prefijo VL solo cuando deja un PL... válido. Los charts oficiales
    /// usan VLOLAK... (verificado) y el servidor los espera íntegros.
    private func stripVL(_ bid: String) -> String {
        if bid.hasPrefix("VL") {
            let rest = String(bid.dropFirst(2))
            if rest.hasPrefix("PL") { return rest }
            if rest.hasPrefix("OLAK") { return bid }
            return rest
        }
        return bid
    }

    /// Charts desde JSON genérico: agrupa musicTwoRowItemRenderer por su carousel/header.
    private func rawChartSections(_ root: [String: Any]) -> [ChartSection] {
        var sections: [ChartSection] = []
        walk(root) { d in
            guard let shelf = d["musicCarouselShelfRenderer"] as? [String: Any] else { return }
            var title = ""
            if let header = shelf["header"] as? [String: Any] {
                if let basic = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any] {
                    title = rawTexts(basic["title"]).joined()
                }
                if title.isEmpty { title = rawTexts(header["title"]).joined() }
            }
            var items: [HomeItem] = []
            if let contents = shelf["contents"] as? [Any] {
                for c in contents {
                    guard let cd = c as? [String: Any],
                          let twoRow = cd["musicTwoRowItemRenderer"] as? [String: Any],
                          let item = rawTwoRowHomeItem(twoRow) else { continue }
                    items.append(item)
                }
            }
            if !items.isEmpty {
                sections.append(ChartSection(title: title.isEmpty ? "Charts" : title, items: items))
            }
        }
        return sections
    }

    /// Álbumes (browseId MPRE*) de cualquier shape TV/WEB.
    private func rawAlbums(_ root: [String: Any]) -> [YTAlbum] {
        var out: [YTAlbum] = []
        var seen = Set<String>()
        walk(root) { d in
            guard let nav = d["navigationEndpoint"] as? [String: Any],
                  let be = nav["browseEndpoint"] as? [String: Any],
                  let bid = be["browseId"] as? String, bid.hasPrefix("MPRE") else { return }
            let title = rawTexts(d["title"]).joined()
            guard !title.isEmpty, !seen.contains(bid) else { return }
            seen.insert(bid)
            let artists = rawTexts(d["subtitle"]).joined(separator: " ")
            let thumb = rawThumb(d["thumbnailRenderer"]) ?? rawThumb(d["thumbnail"])
            out.append(YTAlbum(id: bid, title: title, artists: artists, year: nil, thumbnailUrl: thumb))
        }
        return out
    }

    /// Artistas (browseId UC*) de cualquier shape TV/WEB.
    private func rawArtists(_ root: [String: Any]) -> [YTArtist] {
        var out: [YTArtist] = []
        var seen = Set<String>()
        walk(root) { d in
            guard let nav = d["navigationEndpoint"] as? [String: Any],
                  let be = nav["browseEndpoint"] as? [String: Any],
                  let bid = be["browseId"] as? String, bid.hasPrefix("UC") else { return }
            let name = rawTexts(d["title"]).joined()
            guard !name.isEmpty, !seen.contains(bid) else { return }
            seen.insert(bid)
            let thumb = rawThumb(d["thumbnailRenderer"]) ?? rawThumb(d["thumbnail"])
            out.append(YTArtist(id: bid, name: name, thumbnailUrl: thumb))
        }
        return out
    }

    // MARK: - TV secondary-nav tabs + tiles (librería TV: Your Music Library)

    private struct RawTvTab {
        let browseId: String
        let title: String
        let content: [String: Any]?
    }

    /// Tabs de tvSecondaryNavRenderer: cada tab trae endpoint.browseId + contenido INLINE
    /// (gridRenderer con tileRenderer). Pedir FEmusic_liked_albums devuelve el shell con
    /// TODAS las tabs; el contenido real está en la tab correspondiente.
    private func rawTvTabs(_ root: [String: Any]) -> [RawTvTab] {
        var out: [RawTvTab] = []
        var seen = Set<String>()
        walk(root) { d in
            guard let tab = d["tabRenderer"] as? [String: Any],
                  let ep = tab["endpoint"] as? [String: Any],
                  let be = ep["browseEndpoint"] as? [String: Any],
                  let bid = be["browseId"] as? String,
                  !seen.contains(bid) else { return }
            seen.insert(bid)
            let title = rawTexts(tab["title"]).joined()
            out.append(RawTvTab(browseId: bid, title: title, content: tab["content"] as? [String: Any]))
        }
        return out
    }

    private struct RawTile {
        let contentId: String?
        let title: String
        let subtitle: String
        let thumb: String?
        let watchVideoId: String?
        let browseId: String?
    }

    /// tileRenderer genérico TV: contentId + título (metadata) + endpoints onSelect.
    private func rawTiles(_ node: Any) -> [RawTile] {
        var out: [RawTile] = []
        var seen = Set<String>()
        walk(node) { d in
            guard let tile = d["tileRenderer"] as? [String: Any] else { return }
            let cid = tile["contentId"] as? String
            // Título: metadata.tileMetadataRenderer.title, metadata.title o title directo
            var title = ""
            var subtitle = ""
            if let meta = tile["metadata"] as? [String: Any] {
                if let tmr = meta["tileMetadataRenderer"] as? [String: Any] {
                    title = rawTexts(tmr["title"]).joined()
                    if subtitle.isEmpty { subtitle = rawTexts(tmr["subtitle"]).joined(separator: " ") }
                    if subtitle.isEmpty { subtitle = rawTexts(tmr["lines"]).joined(separator: " ") }
                }
                if title.isEmpty { title = rawTexts(meta["title"]).joined() }
            }
            if title.isEmpty { title = rawTexts(tile["title"]).joined() }
            // Endpoints: onSelectCommand / navigationEndpoint / overlay (cualquier clave *Endpoint)
            var wvid: String?
            var bbid: String?
            let candidates: [Any?] = [tile["onSelectCommand"], tile["navigationEndpoint"], tile["overlay"]]
            for cand in candidates {
                guard let ed = cand as? [String: Any] else { continue }
                if wvid == nil, let we = ed["watchEndpoint"] as? [String: Any], let v = we["videoId"] as? String { wvid = v }
                if bbid == nil, let be = ed["browseEndpoint"] as? [String: Any], let b = be["browseId"] as? String { bbid = b }
            }
            if wvid == nil || bbid == nil {
                for (k, val) in tile where k.hasSuffix("Endpoint") || k.hasSuffix("Command") {
                    guard let ed = val as? [String: Any] else { continue }
                    if wvid == nil, let we = ed["watchEndpoint"] as? [String: Any], let v = we["videoId"] as? String { wvid = v }
                    if bbid == nil {
                        if let be = ed["browseEndpoint"] as? [String: Any], let b = be["browseId"] as? String { bbid = b }
                        else if let nav = ed["navigationEndpoint"] as? [String: Any],
                                let be2 = nav["browseEndpoint"] as? [String: Any], let b2 = be2["browseId"] as? String { bbid = b2 }
                    }
                }
            }
            guard !title.isEmpty else { return }
            let key = "\(cid ?? "-")|\(wvid ?? "-")|\(bbid ?? "-")|\(title)"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            var thumb: String?
            if let header = tile["header"] as? [String: Any],
               let thr = header["tileHeaderRenderer"] as? [String: Any] {
                thumb = rawThumb(thr["thumbnail"]) ?? rawThumb(thr)
            }
            if thumb == nil { thumb = rawThumb(tile["thumbnail"]) }
            out.append(RawTile(contentId: cid, title: title, subtitle: subtitle, thumb: thumb, watchVideoId: wvid, browseId: bbid))
        }
        return out
    }

    /// Tiles de la tab indicada (por browseId o pista de título). Si la tab trae solo
    /// continuación (reloadContinuationData), la sigue (browse+continuation) y parsea el resultado.
    private func rawTvTabTiles(_ root: [String: Any], tabIds: [String], titleHints: [String]) async -> [RawTile] {
        let tabs = rawTvTabs(root)
        var content: [String: Any]?
        for tid in tabIds {
            if let t = tabs.first(where: { $0.browseId == tid }), let c = t.content { content = c; break }
        }
        if content == nil {
            for hint in titleHints {
                if let t = tabs.first(where: { $0.title.lowercased().contains(hint) }), let c = t.content { content = c; break }
            }
        }
        guard let c = content else { return [] }
        var tiles = rawTiles(c)
        if !tiles.isEmpty { return tiles }
        // Sin grid inline: seguir reloadContinuationData (tabs no seleccionadas)
        var contToken: String?
        walk(c) { d in
            if contToken != nil { return }
            if let rc = d["reloadContinuationData"] as? [String: Any],
               let tok = rc["continuation"] as? String { contToken = tok }
        }
        guard let tok = contToken else { return [] }
        do {
            let dict: [String: Any] = try await client.makeRawRequest(
                endpoint: "browse", body: ["continuation": tok],
                clientType: .tv, forceNoAuth: false
            )
            await MainActor.run { DebugLogger.shared.log("📑 tab continuation seguida items?") }
            tiles = rawTiles(dict)
        } catch {
            await MainActor.run { DebugLogger.shared.log("❌ tab continuation \(error)") }
        }
        return tiles
    }

    /// musicTwoRowItemRenderer genérico → HomeItem (playlist VL/PL, álbum MPRE, artista UC).
    private func rawTwoRowHomeItem(_ d: [String: Any]) -> HomeItem? {
        guard let nav = d["navigationEndpoint"] as? [String: Any],
              let be = nav["browseEndpoint"] as? [String: Any],
              let bid = be["browseId"] as? String else { return nil }
        let title = rawTexts(d["title"]).joined()
        guard !title.isEmpty else { return nil }
        let subtitle = rawTexts(d["subtitle"]).joined(separator: " ")
        let thumb = rawThumb(d["thumbnailRenderer"]) ?? rawThumb(d["thumbnail"])
        if bid.hasPrefix("VL") || bid.hasPrefix("PL") {
            let pid = bid.hasPrefix("VL") ? stripVL(bid) : bid
            return .playlist(YTPlaylist(id: pid, name: title, author: subtitle.isEmpty ? nil : subtitle, thumbnailUrl: thumb, songCount: 0, playlistId: nil))
        } else if bid.hasPrefix("MPRE") {
            return .album(YTAlbum(id: bid, title: title, artists: subtitle, year: nil, thumbnailUrl: thumb))
        } else if bid.hasPrefix("UC") {
            return .artist(YTArtist(id: bid, name: title, thumbnailUrl: thumb))
        }
        return nil
    }

    // MARK: - New Releases

    func getNewReleases() async throws -> [YTAlbum] {
        let response = try await browse(browseId: "FEmusic_new_releases_albums")

        guard let sectionContents = response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents else {
            return []
        }

        var albums: [YTAlbum] = []

        for sectionContent in sectionContents {
            if let gridRenderer = sectionContent.gridRenderer {
                if let items = gridRenderer.items {
                    for item in items {
                        if let itemRenderer = item.musicTwoRowItemRenderer,
                           let homeItem = parseHomeItem(itemRenderer),
                           case .album(let album) = homeItem {
                            albums.append(album)
                        }
                    }
                }
            }
        }

        return albums
    }

    // MARK: - Account Playlists

    func getAccountPlaylists() async throws -> [YTPlaylist] {
        guard client.isAuthenticated else {
            throw InnerTubeError.notAuthenticated
        }

        var playlists: [YTPlaylist] = []
        if let response = try? await browseAuthenticated(browseId: "FEmusic_liked_playlists") {
            playlists = parseAccountPlaylists(response)
        }
        if !playlists.isEmpty { return playlists }

        // Fallback for TV client response shape
        do {
            let raw = try await browseRawAuthenticated(browseId: "FEmusic_liked_playlists")
            let rawLists = rawPlaylists(raw)
            if !rawLists.isEmpty { return rawLists }
        } catch {}

        return playlists
    }

    private func parseAccountPlaylists(_ response: BrowseResponse) -> [YTPlaylist] {
        guard let sectionContents = response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents else {
            return []
        }

        var playlists: [YTPlaylist] = []

        for sectionContent in sectionContents {
            // Try grid renderer
            if let gridRenderer = sectionContent.gridRenderer {
                if let items = gridRenderer.items {
                    for item in items {
                        if let itemRenderer = item.musicTwoRowItemRenderer,
                           let homeItem = parseHomeItem(itemRenderer),
                           case .playlist(let playlist) = homeItem {
                            // Filter out "SE" (special "Your Likes" playlist ID)
                            if playlist.id != "SE" {
                                playlists.append(playlist)
                            }
                        }
                    }
                }
            }

            // Try carousel shelf
            if let carouselShelf = sectionContent.musicCarouselShelfRenderer {
                if let contents = carouselShelf.contents {
                    for content in contents {
                        if let itemRenderer = content.musicTwoRowItemRenderer,
                           let homeItem = parseHomeItem(itemRenderer),
                           case .playlist(let playlist) = homeItem {
                            if playlist.id != "SE" {
                                playlists.append(playlist)
                            }
                        }
                    }
                }
            }
        }

        return playlists
    }

    // MARK: - Search Suggestions

    func getSearchSuggestions(query: String) async throws -> [SearchSuggestion] {
        let body: [String: Any] = [
            "input": query
        ]

        let response = try await client.makeRequest(
            endpoint: "music/get_search_suggestions",
            body: body,
            responseType: SearchSuggestionsResponse.self
        )

        return parseSearchSuggestions(response)
    }

    private func parseSearchSuggestions(_ response: SearchSuggestionsResponse) -> [SearchSuggestion] {
        guard let contents = response.contents else { return [] }

        var suggestions: [SearchSuggestion] = []

        for content in contents {
            if let renderer = content.searchSuggestionsSectionRenderer {
                for item in renderer.contents ?? [] {
                    if let suggestionRenderer = item.searchSuggestionRenderer {
                        let text = suggestionRenderer.suggestion?.combined ?? ""
                        if !text.isEmpty {
                            suggestions.append(SearchSuggestion(text: text, isHistory: false))
                        }
                    }
                }
            }
        }

        return suggestions
    }

    // MARK: - Stream URL Validation

    private func validateStreamUrl(_ url: String) async -> Bool {
        guard let streamUrl = URL(string: url) else {
            return false
        }

        do {
            var request = URLRequest(url: streamUrl)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            return (200...299).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }
}

// MARK: - Supporting Types

enum SearchFilter {
    case all
    case songs
    case videos
    case albums
    case playlists
    case artists

    var params: String {
        switch self {
        case .all: return ""
        case .songs: return "EgWKAQIIAWoKEAoQCRADEAQQBQ%3D%3D"
        case .videos: return "EgWKAQIQAWoKEAoQCRADEAQQBQ%3D%3D"
        case .albums: return "EgWKAQIYAWoKEAoQCRADEAQQBQ%3D%3D"
        case .playlists: return "EgWKAQIoAWoKEAoQCRADEAQQBQ%3D%3D"
        case .artists: return "EgWKAQIgAWoKEAoQCRADEAQQBQ%3D%3D"
        }
    }
}

enum SearchResult {
    case song(YTSong)
    case album(YTAlbum)
    case artist(YTArtist)
    case playlist(YTPlaylist)
}

struct EmptyResponse: Codable {}

// MARK: - Charts Models

struct ChartsPage {
    let sections: [ChartSection]
}

struct ChartSection {
    let title: String
    let items: [HomeItem]
}

// MARK: - Search Suggestions Models

struct SearchSuggestion: Identifiable {
    let id = UUID()
    let text: String
    let isHistory: Bool
}

struct SearchSuggestionsResponse: Codable {
    let contents: [SuggestionContent]?

    struct SuggestionContent: Codable {
        let searchSuggestionsSectionRenderer: SearchSuggestionsSectionRenderer?

        struct SearchSuggestionsSectionRenderer: Codable {
            let contents: [SuggestionItem]?

            struct SuggestionItem: Codable {
                let searchSuggestionRenderer: SearchSuggestionRenderer?

                struct SearchSuggestionRenderer: Codable {
                    let suggestion: YTText?
                }
            }
        }
    }
}
