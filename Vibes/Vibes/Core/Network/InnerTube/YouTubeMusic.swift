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

            let id = browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId

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
        var clients: [InnerTubeClientType] = []
        if client.isAuthenticated {
            // SAPISIDHASH solo válido con WEB_REMIX (diagnóstico 401: ANDROID_MUSIC + SAPISID → 401). Para streaming logueado usa WEB_REMIX con Cookie.
            clients.append(contentsOf: [.webRemix, .androidMusic, .android, .ios, .tvEmbedded, .web])
        } else {
            // Unauthenticated: ANDROID permite 1.7M con 200k, IOS throttlea
            clients.append(contentsOf: [.android, .ios, .tvEmbedded, .androidVR, .webRemix, .web])
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
                    // If LOGIN_REQUIRED and we are authenticated, maybe cookies expired -> propagate auth error
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
                    }
                }
            } catch {
                lastError = error
                print("⚠️ [YouTube API] Client \(clientType) request failed: \(error)")
                continue
            }
        }

        // If we had an auth-specific error, propagate it
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
            // Try to fetch assets via WEB_REMIX as fallback (best chance to get js)
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

        // Attempt to deobfuscate throttling parameter (n param)
        let unthrottledUrl = await ThrottlingDecipher.shared.deobfuscate(url: baseUrl, playerResponse: assetsResponse)

        // If we still have no n param (common with Android clients) try WEB formats to get an n-bearing URL
        var finalUrl = unthrottledUrl
        if !unthrottledUrl.contains("n=") {
            if let webFormats = assetsResponse?.streamingData?.adaptiveFormats ?? assetsResponse?.streamingData?.formats,
               let webFormat = selectBestAudioFormat(webFormats),
               let webUrl = webFormat.url ?? decodeSignatureCipher(webFormat.signatureCipher) {
                let det = await ThrottlingDecipher.shared.deobfuscate(url: webUrl, playerResponse: assetsResponse)
                finalUrl = det
            }
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
        var baseUrl = bestFormat.url ?? decodeSignatureCipher(bestFormat.signatureCipher) ?? decodeSignatureCipher(bestFormat.cipher)

        guard let url = baseUrl else {
            throw InnerTubeError.invalidResponse
        }

        // Do NOT add &range query here – googlevideo now rejects full-range query (403)
        // DownloadManager will fetch via Range header in chunks (see DownloadManager.performChunkedDownload)
        // This keeps URL clean for both streaming (AVPlayer via CustomResourceLoader) and chunked download

        return (url: url, contentLength: contentLength, clientType: usedClientType)
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

        // H1: WEB_REMIX+SAPISID 401 → prueba IOS cuando hay sesión (y fallback a noauth si 401)
        let browseClient: InnerTubeClientType = client.isAuthenticated ? .ios : .webRemix
        do {
            return try await client.makeRequest(
                endpoint: "browse",
                body: body,
                clientType: browseClient,
                responseType: BrowseResponse.self
            )
        } catch InnerTubeError.authenticationExpired {
            // Reintenta una vez sin auth (como hace player) antes de propagar 401
            if client.isAuthenticated {
                return try await client.makeRequest(
                    endpoint: "browse",
                    body: body,
                    clientType: .webRemix,
                    responseType: BrowseResponse.self
                )
            }
            throw InnerTubeError.authenticationExpired
        }
    }

    func getAlbum(browseId: String) async throws -> (YTAlbum, [YTSong]) {
        let response = try await browse(browseId: browseId)

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
        
        // Inject album info (thumbnail, albumId, albumName) into each song
        // Album songs often don't have their own thumbnail - use album's thumbnail
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
        let response = try await browse(browseId: browseId)

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

        if let sections = response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents {
            for section in sections {
                if let shelfContents = section.musicPlaylistShelfRenderer?.contents {
                    for content in shelfContents {
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

        // Ensure songs have thumbnail (use playlist thumbnail as fallback if needed)
        let playlistThumbnail = playlist.thumbnailUrl
        let songsWithThumbnails = songs.map { song in
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

    /// Browse with optional params support
    func browseWithParams(browseId: String, params: String? = nil) async throws -> BrowseResponse {
        var body: [String: Any] = [
            "browseId": browseId
        ]

        if let params = params {
            body["params"] = params
        }

        let browseClient: InnerTubeClientType = client.isAuthenticated ? .ios : .webRemix
        do {
            return try await client.makeRequest(
                endpoint: "browse",
                body: body,
                clientType: browseClient,
                responseType: BrowseResponse.self
            )
        } catch InnerTubeError.authenticationExpired where client.isAuthenticated {
            // Fallback sin auth si IOS+Bearer falla (cuenta nueva sin librería)
            return try await client.makeRequest(
                endpoint: "browse",
                body: body,
                clientType: .webRemix,
                responseType: BrowseResponse.self
            )
        }
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
        let response = try await browse(browseId: browseId)
        return parseArtistPage(response, browseId: browseId)
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

            // Remove "VL" prefix if present (matches Android implementation)
            let id = browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId

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

        return try await client.makeRequest(
            endpoint: "next",
            body: body,
            responseType: NextResponse.self
        )
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
            response = try await browse(browseId: "FEmusic_liked_playlists")
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

        await MainActor.run { DebugLogger.shared.log("📚 parsed \(playlists.count) playlists") }
        return playlists
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

        let response = try await browse(browseId: "FEmusic_history")
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
        return parseChartsPage(response)
    }

    private func parseChartsPage(_ response: BrowseResponse) -> ChartsPage {
        guard let sectionContents = response.contents?.singleColumnBrowseResultsRenderer?.tabs?.first?.tabRenderer?.content?.sectionListRenderer?.contents else {
            return ChartsPage(sections: [])
        }

        var sections: [ChartSection] = []

        for sectionContent in sectionContents {
            if let carouselShelf = sectionContent.musicCarouselShelfRenderer {
                let title = carouselShelf.header?.musicCarouselShelfBasicHeaderRenderer?.title?.combined ?? ""
                var items: [HomeItem] = []

                if let contents = carouselShelf.contents {
                    for content in contents {
                        if let itemRenderer = content.musicTwoRowItemRenderer,
                           let item = parseHomeItem(itemRenderer) {
                            items.append(item)
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

        let response = try await browse(browseId: "FEmusic_liked_playlists")
        return parseAccountPlaylists(response)
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
