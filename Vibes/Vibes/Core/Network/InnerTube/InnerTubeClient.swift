import Foundation

enum InnerTubeClientType: String {
    case webRemix = "WEB_REMIX"
    case web = "WEB"
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
        return cookies != nil
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
        let (clientName, clientVersion, userAgent) = getClientInfo(for: clientType)

        // Determine which clients support login (matching Android)
        let loginSupported: Bool
        switch clientType {
        case .webRemix, .webCreator, .tvEmbedded:
            loginSupported = true
        case .ios, .android, .androidMusic, .androidVR, .web:
            loginSupported = false
        }

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
            osVersion = "17.5.1.21F90"
        case .android, .androidMusic:
            deviceMake = "Google"
            deviceModel = "Pixel 8"
            osName = "Android"
            osVersion = "13"
            androidSdkVersion = "33"
        case .androidVR:
            deviceMake = "Oculus"
            deviceModel = "Quest 3"
            osName = "Android"
            osVersion = "12"
            androidSdkVersion = "32"
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
                onBehalfOfUser: (isAuthenticated && loginSupported) ? dataSyncId : nil  // Only send dataSyncId if client supports login
            )
        )
    }

    private func getClientInfo(for clientType: InnerTubeClientType) -> (String, String, String?) {
        switch clientType {
        case .webRemix:
            return ("WEB_REMIX", "1.20220606.03.00", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.157 Safari/537.36")
        case .web:
            return ("WEB", "2.2021111", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.157 Safari/537.36")
        case .tvEmbedded:
            return ("TVHTML5_SIMPLY_EMBEDDED_PLAYER", "2.0", "Mozilla/5.0 (PlayStation 4 5.55) AppleWebKit/601.2 (KHTML, like Gecko)")
        case .webCreator:
            return ("WEB_CREATOR", "1.20220606.03.00", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.157 Safari/537.36")
        case .ios:
            return ("IOS", "19.29.1", "com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)")
        case .android:
            return ("ANDROID", "17.13.3", "Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Mobile Safari/537.36")
        case .androidMusic:
            return ("ANDROID_MUSIC", "5.01", "Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Mobile Safari/537.36")
        case .androidVR:
            return ("ANDROID_VR", "1.43.32", "com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)")
        }
    }

    private func buildRequest(
        endpoint: String,
        body: [String: Any],
        clientType: InnerTubeClientType = .webRemix
    ) -> URLRequest? {
        let key = apiKey(for: clientType)
        guard let url = URL(string: "\(baseURL)/\(endpoint)?key=\(key)&prettyPrint=false") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Referer")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "x-origin")

        // Add YouTube-specific headers (matching InnerTune-dev implementation)
        let (clientName, clientVersion, userAgent) = getClientInfo(for: clientType)
        request.setValue(clientName, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")

        // CRITICAL: User-Agent header
        // URLSession may override this, so we also need to configure URLSessionConfiguration
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        // Determine if client supports login (matching Android logic)
        let loginSupported: Bool
        switch clientType {
        case .webRemix, .webCreator, .tvEmbedded:
            loginSupported = true
        case .ios, .android, .androidMusic, .androidVR, .web:
            loginSupported = false
        }

        // Only send cookies if client supports login (matching Android ytClient logic)
        if let cookies = cookies, loginSupported {
            request.setValue(cookies, forHTTPHeaderField: "Cookie")

            // Add SAPISIDHASH for authenticated requests
            if let sapisidHash = generateSAPISIDHASH() {
                request.setValue(sapisidHash, forHTTPHeaderField: "Authorization")
            }
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
        // Matching Android implementation exactly
        guard cookies != nil else {
            return nil
        }

        // Check if SAPISID exists in cookieMap (matching Android line 107)
        guard let sapisid = cookieMap["SAPISID"] else {
            return nil
        }

        // Generate hash (matching Android lines 108-110)
        let currentTime = Int(Date().timeIntervalSince1970)
        let origin = "https://music.youtube.com"
        let hashInput = "\(currentTime) \(sapisid) \(origin)"

        guard let data = hashInput.data(using: .utf8) else { return nil }
        let hash = SHA1.hash(data: data)

        return "SAPISIDHASH \(currentTime)_\(hash)"
    }

    // MARK: - API Methods

    func makeRequest<T: Decodable>(
        endpoint: String,
        body: [String: Any],
        clientType: InnerTubeClientType = .webRemix,
        responseType: T.Type
    ) async throws -> T {
        guard let request = buildRequest(endpoint: endpoint, body: body, clientType: clientType) else {
            throw InnerTubeError.invalidRequest
        }

        // Use custom URLSession that respects User-Agent header
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InnerTubeError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
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
        responseType: T.Type
    ) async throws -> T {
        let body: [String: Any] = [
            "continuation": continuation
        ]
        return try await makeRequest(endpoint: endpoint, body: body, clientType: clientType, responseType: responseType)
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