import Foundation

enum InnerTubeClientType: String {
    case webRemix = "WEB_REMIX"
    case web = "WEB"
    case tvEmbedded = "TVHTML5_SIMPLY_EMBEDDED_PLAYER"
    case webCreator = "WEB_CREATOR"
    case ios = "IOS_MUSIC"
    case android = "ANDROID_MUSIC"
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
    private let apiKey = "YOUR_API_KEY_HERE"

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
        case .ios, .android, .androidVR, .web:
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
            osVersion = "18.0.0.22A3354"
        case .android:
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
                visitorData: visitorData,
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
            return ("WEB_REMIX", "1.20250310.01.00", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0")
        case .web:
            return ("WEB", "2.20250312.04.00", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0")
        case .tvEmbedded:
            return ("TVHTML5_SIMPLY_EMBEDDED_PLAYER", "2.0", "Mozilla/5.0 (PlayStation; PlayStation 4/12.02) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15")
        case .webCreator:
            return ("WEB_CREATOR", "1.20250312.03.01", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0")
        case .ios:
            return ("IOS_MUSIC", "7.51", "com.google.ios.youtube.music/7.51 (iPhone; U; CPU iOS 18_0 like Mac OS X)")
        case .android:
            return ("ANDROID_MUSIC", "7.51.52", "com.google.android.apps.youtube.music/7.51.52 (Linux; U; Android 13)")
        case .androidVR:
            return ("ANDROID_VR", "1.43.32", "com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)")
        }
    }

    private func buildRequest(
        endpoint: String,
        body: [String: Any],
        clientType: InnerTubeClientType = .webRemix
    ) -> URLRequest? {
        guard let url = URL(string: "\(baseURL)/\(endpoint)?key=\(apiKey)&prettyPrint=false") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Referer")

        // Add YouTube-specific headers (matching Android implementation)
        let (_, clientVersion, userAgent) = getClientInfo(for: clientType)
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")  // WEB_REMIX client ID
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
        case .ios, .android, .androidVR, .web:
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
