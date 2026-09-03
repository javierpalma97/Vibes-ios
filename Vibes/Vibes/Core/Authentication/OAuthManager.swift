import Foundation
import Combine

// MARK: - YouTube OAuth2 via TV/device flow (como MusicBot #1670 / lavaplayer #33, yt-dlp --allow-unplayable-formats)
// Usa el client TV público de YouTube: 861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com
// Scope: https://www.googleapis.com/auth/youtube (solo lectura de librería/historial, no sube nada)
// Flujo: device/code → usuario va a https://www.google.com/device y mete user_code → poll token → Bearer

@MainActor
class OAuthManager: ObservableObject {
    static let shared = OAuthManager()

    @Published var isAuthenticated: Bool = false
    @Published var accessToken: String?
    @Published var refreshToken: String?
    @Published var expiresAt: Date?

    // Helpers no-MainActor para InnerTubeClient (evita Swift 6 isolation errors)
    nonisolated static var isAuthenticatedSync: Bool {
        UserDefaults.standard.string(forKey: "yt_oauth_access_token") != nil
    }
    nonisolated static var bearerHeaderSync: String? {
        guard let t = UserDefaults.standard.string(forKey: "yt_oauth_access_token"), !t.isEmpty else { return nil }
        return "Bearer \(t)"
    }

    private let clientId = "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com"
    private let clientSecret = "SboVhoG9s0rNafixCSGGKXAT" // pytube/yt-dlp TV public (MusicBot #1670)
    private let scope = "https://www.googleapis.com/auth/youtube"
    private let deviceCodeURL = URL(string: "https://oauth2.googleapis.com/device/code")!
    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    // Guardado simple en UserDefaults (Keychain sería mejor, pero así es visible para debug)
    private let kAccess = "yt_oauth_access_token"
    private let kRefresh = "yt_oauth_refresh_token"
    private let kExpiry = "yt_oauth_expiry"
    private let kVisitor = "yt_oauth_visitor_data"

    private init() { load() }

    private func load() {
        accessToken = UserDefaults.standard.string(forKey: kAccess)
        refreshToken = UserDefaults.standard.string(forKey: kRefresh)
        if let t = UserDefaults.standard.object(forKey: kExpiry) as? TimeInterval {
            expiresAt = Date(timeIntervalSince1970: t)
        }
        isAuthenticated = accessToken != nil && !(accessToken?.isEmpty ?? true)
        if isAuthenticated { print("🔐 [OAuth] cargado token \(accessToken?.prefix(20) ?? "")...") }
    }

    private func save(access: String?, refresh: String?, expiresIn: Int?) {
        if let a = access { UserDefaults.standard.set(a, forKey: kAccess); accessToken = a }
        if let r = refresh { UserDefaults.standard.set(r, forKey: kRefresh); refreshToken = r }
        if let e = expiresIn { let d = Date().addingTimeInterval(TimeInterval(e)); UserDefaults.standard.set(d.timeIntervalSince1970, forKey: kExpiry); expiresAt = d }
        isAuthenticated = accessToken != nil && !(accessToken?.isEmpty ?? true)
        DebugLogger.shared.log("🔐 OAuth save isAuth=\(isAuthenticated) access=\(access?.prefix(20) ?? "nil")...")
        print("🔐 [OAuth] save isAuth=\(isAuthenticated)")
        NotificationCenter.default.post(name: NSNotification.Name("OAuthAuthChanged"), object: nil)
        Task { @MainActor in AuthenticationManager.shared.refreshAuthState() }
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: kAccess)
        UserDefaults.standard.removeObject(forKey: kRefresh)
        UserDefaults.standard.removeObject(forKey: kExpiry)
        accessToken = nil; refreshToken = nil; expiresAt = nil; isAuthenticated = false
        DebugLogger.shared.log("🔐 OAuth signOut")
        NotificationCenter.default.post(name: NSNotification.Name("OAuthAuthChanged"), object: nil)
    }

    // Import ytmusicapi oauth.json (tiene access_token, refresh_token, scope, token_type)
    @MainActor func importOAuthJson(data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        // ytmusicapi guarda {access_token, refresh_token, expires_in, ...} o a veces {token: {access_token...}}
        var at: String? = json?["access_token"] as? String ?? json?["accessToken"] as? String
        var rt: String? = json?["refresh_token"] as? String ?? json?["refreshToken"] as? String
        var exp: Int? = json?["expires_in"] as? Int ?? json?["expiresIn"] as? Int
        // fallback: si el json es { "token": "ya29..." }
        if at == nil, let token = json?["token"] as? String { at = token }
        if at == nil { throw OAuthError.requestFailed("oauth.json sin access_token") }
        // ytmusicapi a veces guarda el token en plain sin refresh, asumimos 1h
        if exp == nil { exp = 3600 }
        save(access: at, refresh: rt, expiresIn: exp)
        DebugLogger.shared.log("✅ OAuth import \(at!.prefix(10)) rt=\(rt != nil) exp=\(exp!)")
    }

    var bearerHeader: String? {
        guard let t = accessToken, !t.isEmpty else { return nil }
        // Si expira en <60s, intenta refresh sincrónico (no bloqueante, el caller puede reintentar)
        if let exp = expiresAt, exp.timeIntervalSinceNow < 60, let rt = refreshToken {
            Task { try? await self.refresh() }
        }
        return "Bearer \(t)"
    }

    // MARK: - Device flow

    struct DeviceCodeResponse: Decodable {
        let device_code: String
        let user_code: String
        let verification_url: String
        let verification_url_qr: String?
        let expires_in: Int
        let interval: Int
    }

    struct TokenResponse: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expires_in: Int?
        let token_type: String?
        let error: String?
        let error_description: String?
    }

    func startDeviceFlow() async throws -> DeviceCodeResponse {
        var req = URLRequest(url: deviceCodeURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(clientId)&scope=\(scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scope)"
        req.httpBody = body.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? ""
            DebugLogger.shared.log("❌ device/code HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1) \(txt.prefix(300))")
            throw OAuthError.requestFailed(txt)
        }
        let dec = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
        DebugLogger.shared.log("📱 device_code \(dec.user_code) url=\(dec.verification_url) interval=\(dec.interval)")
        return dec
    }

    func pollForToken(deviceCode: String, interval: Int) async throws -> TokenResponse {
        // Sesión que sobrevive a background/suspensión (tu log: network connection was lost al minimizar)
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config)
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let sleepNs = UInt64((interval + 1) * 1_000_000_000)
        let deadline = Date().addingTimeInterval(600) // 10 min
        var networkFails = 0
        while Date() < deadline {
            // Permite cancelación desde la UI sin matar la sesión
            if Task.isCancelled { throw OAuthError.expired }
            let body = "client_id=\(clientId)&client_secret=\(clientSecret)&device_code=\(deviceCode)&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"
            req.httpBody = body.data(using: .utf8)
            do {
                let (data, _) = try await session.data(for: req)
                networkFails = 0
                let token = try JSONDecoder().decode(TokenResponse.self, from: data)
                if let err = token.error {
                    if err == "authorization_pending" {
                        DebugLogger.shared.log("⏳ poll pending...")
                        try? await Task.sleep(nanoseconds: sleepNs)
                        continue
                    } else if err == "slow_down" {
                        try? await Task.sleep(nanoseconds: sleepNs + 2_000_000_000)
                        continue
                    } else if err == "expired_token" {
                        DebugLogger.shared.log("❌ device_code expired")
                        throw OAuthError.expired
                    } else {
                        DebugLogger.shared.log("❌ poll error \(err) \(token.error_description ?? "")")
                        throw OAuthError.requestFailed(err)
                    }
                }
                if let at = token.access_token {
                    save(access: at, refresh: token.refresh_token, expiresIn: token.expires_in)
                    DebugLogger.shared.log("✅ OAuth token ok expires_in=\(token.expires_in ?? -1)")
                    return token
                }
            } catch let e as URLError {
                // No aborta en pérdida de red (tu caso WiFi 1min): reintenta hasta 10 veces
                networkFails += 1
                DebugLogger.shared.log("⚠️ poll network lost (\(networkFails)/10) reintentando... \(e.localizedDescription)")
                if networkFails >= 10 { throw OAuthError.requestFailed("network lost x10: \(e.localizedDescription)") }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                continue
            }
            try? await Task.sleep(nanoseconds: sleepNs)
        }
        throw OAuthError.expired
    }

    func refresh() async throws {
        guard let rt = refreshToken else { throw OAuthError.noRefreshToken }
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(clientId)&client_secret=\(clientSecret)&refresh_token=\(rt)&grant_type=refresh_token"
        req.httpBody = body.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? ""
            DebugLogger.shared.log("❌ refresh HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1) \(txt.prefix(200))")
            throw OAuthError.requestFailed(txt)
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let at = token.access_token {
            save(access: at, refresh: token.refresh_token ?? rt, expiresIn: token.expires_in)
        } else {
            throw OAuthError.requestFailed(token.error ?? "no access_token")
        }
    }
}

enum OAuthError: Error, LocalizedError {
    case requestFailed(String)
    case expired
    case noRefreshToken
    var errorDescription: String? {
        switch self {
        case .requestFailed(let s): return "OAuth: \(s)"
        case .expired: return "Código expirado, reintenta"
        case .noRefreshToken: return "Sin refresh_token"
        }
    }
}
