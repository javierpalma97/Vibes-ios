import Foundation

enum InnerTubeClientType: String {
    case webRemix = "WEB_REMIX"
    case web = "WEB"
    case tv = "TVHTML5"
    case tvEmbedded = "TVHTML5_SIMPLY_EMBEDDED_PLAYER"
    case webCreator = "WEB_CREATOR"
    case ios = "IOS"
    case android = "ANDROID"
    case androidMusic = "ANDROID_MUSIC"
    case androidVR = "ANDROID_VR"
}

struct InnerTubeContext: Codable {
    let client: ClientInfo
    let thirdParty: ThirdPartyInfo?
    let request: RequestInfo
    let user: UserInfo

    struct ClientInfo: Codable {
        let clientName: String
        let clientVersion: String
        let gl: String
        let hl: String
        let visitorData: String?
        let deviceMake: String?
        let deviceModel: String?
        let osName: String?
        let osVersion: String?
        let androidSdkVersion: String?
        // Note: userAgent is sent as HTTP header only, NOT in request body (matching Android)
    }

    struct ThirdPartyInfo: Codable {
        let embedUrl: String
    }

    struct RequestInfo: Codable {
        let internalExperimentFlags: [String]
        let useSsl: Bool
    }

    struct UserInfo: Codable {
        let lockedSafetyMode: Bool
        let onBehalfOfUser: String?  // This is the dataSyncId
    }
}

class InnerTubeClient {
    static let shared = InnerTubeClient()

    private let baseURL = "https://music.youtube.com/youtubei/v1"

    // Default visitor data (matching InnerTune-dev)
    private let defaultVisitorData = "CgtsZG1ySnZiQWtSbyiMjuGSBg%3D%3D"

    // Load API keys from plist file
    private func apiKey(for clientType: InnerTubeClientType) -> String {
        let keyName: String
        switch clientType {
        case .webRemix: keyName = "WEB_REMIX_API_KEY"
        case .web: keyName = "WEB_API_KEY"
        case .tv: keyName = "TVHTML5_API_KEY"
        case .tvEmbedded: keyName = "TVHTML5_API_KEY"
        case .webCreator: keyName = "WEB_REMIX_API_KEY"
        case .ios: keyName = "IOS_API_KEY"
        case .android: keyName = "ANDROID_API_KEY"
        case .androidMusic: keyName = "ANDROID_MUSIC_API_KEY"
        case .androidVR: keyName = "ANDROID_MUSIC_API_KEY"
        }

        if let path = Bundle.main.path(forResource: "APIKeys", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let key = plist[keyName] as? String,
           !key.isEmpty && key != "YOUR_API_KEY_HERE" {
            return key
        }

        // Fallback to default keys (matching InnerTune-dev)
        switch clientType {
        case .webRemix: return "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
        case .web: return "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX3"
        case .tv: return "AIzaSyDCU8hByM-4DrUqRUYnGn-3llEO78bcxq8"
        case .tvEmbedded: return "AIzaSyDCU8hByM-4DrUqRUYnGn-3llEO78bcxq8"
        case .webCreator: return "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
        case .ios: return "AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc"
        case .android: return "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w"
        case .androidMusic: return "AIzaSyAOghZGza2MQSZkY_zfZ370N-PUdXEo8AI"
        case .androidVR: return "AIzaSyAOghZGza2MQSZkY_zfZ370N-PUdXEo8AI"
        }
    }

    private var visitorData: String?
    private var dataSyncId: String?
    private var cookies: String?  // All cookies (for persistence)
    private var cookieMap: [String: String] = [:]  // Parsed cookies for SAPISIDHASH

    // Custom URLSession that doesn't override User-Agent
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Allow custom User-Agent header (don't override it)
        config.httpAdditionalHeaders = [:]
        return URLSession(configuration: config)
    }()

    private init() {
        loadAuthData()
    }

    // MARK: - Authentication

    func setAuthData(cookies: String, visitorData: String, dataSyncId: String) {
        self.cookies = cookies
        self.visitorData = visitorData
        self.dataSyncId = dataSyncId

        // Parse all cookies into map for SAPISIDHASH
        self.cookieMap = parseCookieString(cookies)

        saveAuthData()
    }

    func clearAuthData() {
        self.cookies = nil
        self.visitorData = nil
        self.dataSyncId = nil
        saveAuthData()
    }

    var isAuthenticated: Bool {
        // Cookie auth o OAuth2 Bearer (MusicBot #1670) – usa sync helpers para no-MainActor
        if OAuthManager.isAuthenticatedSync { return true }
        return cookies != nil && !(cookies?.isEmpty ?? true)
    }

    var currentCookies: String? { cookies }

    var debugAuthState: String {
        let oauth = OAuthManager.bearerHeaderSync != nil ? "oauth=\(OAuthManager.bearerHeaderSync!.prefix(10))" : "oauth=nil"
        return "cookies=\(cookies != nil ? "\(cookies!.prefix(20))..." : "nil") visitorData=\(visitorData?.prefix(20) ?? "nil") dataSyncId=\(dataSyncId?.prefix(20) ?? "nil") mapSAPISID=\(cookieMap["SAPISID"] != nil || cookieMap["__Secure-3PAPISID"] != nil) \(oauth)"
    }

    func getUserAgent(for clientType: InnerTubeClientType) -> String {
        let (_, _, userAgent) = getClientInfo(for: clientType)
        return userAgent ?? "Mozilla/5.0"
    }

    private func saveAuthData() {
        UserDefaults.standard.set(cookies, forKey: "innerTubeCookies")
        UserDefaults.standard.set(visitorData, forKey: "innerTubeVisitorData")
        UserDefaults.standard.set(dataSyncId, forKey: "innerTubeDataSyncId")
    }

    private func loadAuthData() {
        cookies = UserDefaults.standard.string(forKey: "innerTubeCookies")
        visitorData = UserDefaults.standard.string(forKey: "innerTubeVisitorData")
        dataSyncId = UserDefaults.standard.string(forKey: "innerTubeDataSyncId")

        // Clean up dataSyncId if it has trailing pipes (migration fix)
        if let rawDataSyncId = dataSyncId, rawDataSyncId.hasSuffix("||") || rawDataSyncId.hasSuffix("|") {
            let cleaned = rawDataSyncId.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            dataSyncId = cleaned
            UserDefaults.standard.set(cleaned, forKey: "innerTubeDataSyncId")
        }

        // Parse cookies into map
        if let cookies = cookies {
            cookieMap = parseCookieString(cookies)
        }
    }

    // MARK: - Request Building

    private func buildContext(clientType: InnerTubeClientType = .webRemix, videoId: String? = nil) -> InnerTubeContext {
        let (clientName, clientVersion, _) = getClientInfo(for: clientType)

        // Determine device/OS fields based on client type
        var deviceMake: String? = nil
        var deviceModel: String? = nil
        var osName: String? = nil
        var osVersion: String? = nil
        var androidSdkVersion: String? = nil

        switch clientType {
        case .ios:
            deviceMake = "Apple"
            deviceModel = "iPhone16,2"  // iPhone 15 Pro
            osName = "iOS"
            osVersion = "18.1.0.22B83"
        case .android, .androidMusic:
            deviceMake = "Google"
            deviceModel = "Pixel 8"
            osName = "Android"
            osVersion = "14"
            androidSdkVersion = "34"
        case .androidVR:
            deviceMake = "Oculus"
            deviceModel = "Quest 3"
            osName = "Android"
            osVersion = "14"
            androidSdkVersion = "34"
        default:
            break
        }

        // Add thirdParty for embedded clients (matching Android implementation)
        var thirdParty: InnerTubeContext.ThirdPartyInfo? = nil
        if clientType == .tvEmbedded, let videoId = videoId {
            thirdParty = InnerTubeContext.ThirdPartyInfo(embedUrl: "https://www.youtube.com/watch?v=\(videoId)")
        }

        return InnerTubeContext(
            client: InnerTubeContext.ClientInfo(
                clientName: clientName,
                clientVersion: clientVersion,
                gl: "US",
                hl: "en",
                visitorData: visitorData ?? defaultVisitorData,
                deviceMake: deviceMake,
                deviceModel: deviceModel,
                osName: osName,
                osVersion: osVersion,
                androidSdkVersion: androidSdkVersion
            ),
            thirdParty: thirdParty,
            request: InnerTubeContext.RequestInfo(
                internalExperimentFlags: [],
                useSsl: true
            ),
            user: InnerTubeContext.UserInfo(
                lockedSafetyMode: false,
                onBehalfOfUser: nil // H3: dataSyncId 11746… numérico causa 401 incluso con cookie válida – InnerTune lo omite para browse
            )
        )
    }

    private func getClientInfo(for clientType: InnerTubeClientType) -> (String, String, String?) {
        switch clientType {
        case .webRemix:
            return ("WEB_REMIX", "1.20250224.01.00", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        case .web:
            return ("WEB", "2.20250222.10.00", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        case .tv:
            // YouTube.js: OAuth2 solo funciona con cliente TV (LuanRT docs 2026-05-12)
            return ("TVHTML5", "7.20250224", "Mozilla/5.0 (SMART-TV; Linux; Tizen 7.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/20.0 TV Safari/537.36")
        case .tvEmbedded:
            return ("TVHTML5_SIMPLY_EMBEDDED_PLAYER", "2.0", "Mozilla/5.0 (PlayStation 5 12.02) AppleWebKit/605.1.15 (KHTML, like Gecko)")
        case .webCreator:
            return ("WEB_CREATOR", "1.20250224.01.00", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
        case .ios:
            return ("IOS", "20.42.02", "com.google.ios.youtube/20.42.02 (iPhone16,2; U; CPU iOS 18_1 like Mac OS X; en_US)")
        case .android:
            return ("ANDROID", "20.07.39", "com.google.android.youtube/20.07.39 (Linux; U; Android 14; Pixel 8 Build/UP1A.231005.007) gzip")
        case .androidMusic:
            return ("ANDROID_MUSIC", "8.23.33", "com.google.android.apps.youtube.music/8.23.33 (Linux; U; Android 14; Pixel 8 Build/UP1A.231005.007) gzip")
        case .androidVR:
            return ("ANDROID_VR", "1.57.08", "com.google.android.apps.youtube.vr.oculus/1.57.08 (Linux; U; Android 14; Quest 3; Build/UKQ1.231005.007; Cronet/118.0.5993.111)")
        }
    }

    private func buildRequest(
        endpoint: String,
        body: [String: Any],
        clientType: InnerTubeClientType = .webRemix,
        forceNoAuth: Bool = false
    ) -> URLRequest? {
        let key = apiKey(for: clientType)
        guard let url = URL(string: "\(baseURL)/\(endpoint)?key=\(key)&prettyPrint=false") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "X-Origin")
        request.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")

        // Add YouTube-specific headers (matching InnerTune-dev implementation)
        let (clientName, clientVersion, userAgent) = getClientInfo(for: clientType)
        request.setValue(clientName, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        if let vd = visitorData ?? defaultVisitorData as String? {
            request.setValue(vd, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        // CRITICAL: User-Agent header
        // URLSession may override this, so we also need to configure URLSessionConfiguration
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        // Send cookies for authenticated requests – but NOT for player with ANDROID/IOS
        // (player with ANDROID/IOS works without auth and 403 with stale SAPISIDHASH; see logs client=auth -> 403)
        // forceNoAuth permite reintentos sin auth aunque haya sesión (fallback H1)
        let shouldSendAuth = {
            if forceNoAuth { return false }
            if !isAuthenticated { return false }
            if endpoint == "player" && (clientType == .android || clientType == .ios) {
                return false
            }
            return true
        }()
        let effectiveIsAuth = !forceNoAuth && isAuthenticated
        // OAuth2 Bearer tiene prioridad sobre SAPISIDHASH (MusicBot #1670 / youtube-source#33)
        // Si forceNoAuth, tampoco mandamos Bearer
        if !forceNoAuth, let bearer = OAuthManager.bearerHeaderSync {
            request.setValue(bearer, forHTTPHeaderField: "Authorization")
            // Para OAuth, no mandamos Cookie SAPISIDHASH, solo Bearer + visitorData
            Task { @MainActor in DebugLogger.shared.log("🔑 oauth \(endpoint) \(clientType) Bearer=\(bearer.prefix(30))") }
            print("🔑 [OAuth] \(endpoint) \(clientType) Bearer=\(bearer.prefix(30))")
            // Si hay cookies, las mandamos también como fallback pero sin SAPISIDHASH
            if shouldSendAuth, let cookies = cookies {
                request.setValue(cookies, forHTTPHeaderField: "Cookie")
            }
        } else if shouldSendAuth, let cookies = cookies {
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
            if let sapisidHash = generateSAPISIDHASH() {
                request.setValue(sapisidHash, forHTTPHeaderField: "Authorization")
                Task { @MainActor in DebugLogger.shared.log("🔑 auth \(endpoint) \(clientType) CookieLen=\(cookies.count) SAPISIDHASH=\(sapisidHash.prefix(30))") }
                print("🔑 [Auth] \(endpoint) \(clientType) CookieLen=\(cookies.count) SAPISIDHASH=\(sapisidHash.prefix(30))")
            } else {
                Task { @MainActor in DebugLogger.shared.log("⚠️ no SAPISIDHASH for \(endpoint) \(clientType) cookiesLen=\(cookies.count) map=\(cookieMap.keys.sorted().prefix(5))") }
                print("⚠️ [Auth] no SAPISIDHASH for \(endpoint) \(clientType) cookiesLen=\(cookies.count) map=\(cookieMap.keys.sorted().prefix(5))")
            }
        } else if effectiveIsAuth && endpoint != "player" {
            let isOAuth = OAuthManager.isAuthenticatedSync
            Task { @MainActor in DebugLogger.shared.log("⚠️ shouldSendAuth false for \(endpoint) \(clientType) isAuth=\(effectiveIsAuth) oauth=\(isOAuth) forceNoAuth=\(forceNoAuth)") }
            print("⚠️ [Auth] shouldSendAuth false for \(endpoint) \(clientType) oauth=\(isOAuth) forceNoAuth=\(forceNoAuth)")
        }

        // Build request body with context
        var requestBody = body
        // Extract videoId from body if present for thirdParty context
        let videoId = body["videoId"] as? String
        let context = buildContext(clientType: clientType, videoId: videoId)
        requestBody["context"] = try? JSONSerialization.jsonObject(
            with: JSONEncoder().encode(context)
        )

        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        return request
    }

    private func generateSAPISIDHASH() -> String? {
        guard cookies != nil else {
            print("⚠️ [Auth] generateSAPISIDHASH no cookies")
            return nil
        }

        // Try SAPISID first, then __Secure-3PAPISID (modern YouTube uses Secure prefix)
        let sapisid = cookieMap["SAPISID"]
            ?? cookieMap["__Secure-3PAPISID"]
            ?? cookieMap["__Secure-3PSID"]
            ?? cookieMap["APISID"]
            ?? cookieMap["__Secure-1PAPISID"]

        guard let sid = sapisid, !sid.isEmpty else {
            print("⚠️ [Auth] SAPISID vacío mapKeys=\(cookieMap.keys.sorted()) cookiesLen=\(cookies?.count ?? 0)")
            Task { @MainActor in DebugLogger.shared.log("⚠️ SAPISID vacío map=\(self.cookieMap.keys.sorted().prefix(5)) len=\(self.cookies?.count ?? 0)") }
            return nil
        }
        // Log sapisid prefix for debug (no exponer completo)
        print("🔑 [Auth] SAPISID=\(sid.prefix(10))... origin=https://music.youtube.com")

        let currentTime = Int(Date().timeIntervalSince1970)
        let origin = "https://music.youtube.com"
        let hashInput = "\(currentTime) \(sid) \(origin)"

        guard let data = hashInput.data(using: .utf8) else { return nil }
        let hash = SHA1.hash(data: data)

        return "SAPISIDHASH \(currentTime)_\(hash)"
    }

    // MARK: - API Methods

    func makeRequest<T: Decodable>(
        endpoint: String,
        body: [String: Any],
        clientType: InnerTubeClientType = .webRemix,
        forceNoAuth: Bool = false,
        responseType: T.Type
    ) async throws -> T {
        guard let request = buildRequest(endpoint: endpoint, body: body, clientType: clientType, forceNoAuth: forceNoAuth) else {
            throw InnerTubeError.invalidRequest
        }

        // Use custom URLSession that respects User-Agent header
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InnerTubeError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Map 401/403 to authenticationExpired when logged in (session expired)
            // Si hay Bearer OAuth, no es expirado de cookie, es falta de scope – no hacer signOut automático
            // Si forceNoAuth, no es error de sesión, es solo que ese cliente no necesita auth
            if (httpResponse.statusCode == 401 || httpResponse.statusCode == 403) && !forceNoAuth && (isAuthenticated || OAuthManager.isAuthenticatedSync) {
                let bodyPreview = String(data: data.prefix(500), encoding: .utf8) ?? ""
                let isAuth = isAuthenticated
                let isOAuth = OAuthManager.isAuthenticatedSync
                let dbg = debugAuthState
                await MainActor.run { DebugLogger.shared.log("❌ HTTP \(httpResponse.statusCode) \(endpoint) isAuth=\(isAuth) oauth=\(isOAuth) \(dbg) body=\(bodyPreview.prefix(200))") }
                print("❌ [InnerTube] HTTP \(httpResponse.statusCode) \(endpoint) \(dbg) oauth=\(isOAuth) body=\(bodyPreview.prefix(500))")
                throw InnerTubeError.authenticationExpired
            }
            throw InnerTubeError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()

        do {
            let result = try decoder.decode(T.self, from: data)
            return result
        } catch {
            throw InnerTubeError.decodingError(error)
        }
    }

    /// Make a continuation request (for paginated content)
    func makeContinuationRequest<T: Decodable>(
        endpoint: String,
        continuation: String,
        clientType: InnerTubeClientType = .webRemix,
        forceNoAuth: Bool = false,
        responseType: T.Type
    ) async throws -> T {
        let body: [String: Any] = [
            "continuation": continuation
        ]
        return try await makeRequest(endpoint: endpoint, body: body, clientType: clientType, forceNoAuth: forceNoAuth, responseType: responseType)
    }
}

enum InnerTubeError: Error {
    case invalidRequest
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case notAuthenticated
    case authenticationExpired
    case playbackNotAllowed(reason: String?)
}

// Simple SHA1 implementation for SAPISIDHASH
struct SHA1 {
    static func hash(data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

// Parse cookie string into map (matching Android's parseCookieString)
private func parseCookieString(_ cookie: String) -> [String: String] {
    var result: [String: String] = [:]

    cookie.split(separator: ";")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .forEach { part in
            if let splitIndex = part.firstIndex(of: "=") {
                let key = String(part[..<splitIndex])
                let value = String(part[part.index(after: splitIndex)...])
                result[key] = value
            }
        }

    return result
}