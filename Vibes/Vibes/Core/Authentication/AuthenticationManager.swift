import Foundation
import WebKit
import Combine

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published var isAuthenticated: Bool = false
    @Published var accountName: String?
    @Published var accountEmail: String?
    @Published var accountImageUrl: String?

    private let innerTube = InnerTubeClient.shared

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Login por cookies (WebView/SAPISID) retirado: solo OAuth2. Se limpian
        // restos de sesiones cookie persistidas para no autenticar con ellas.
        innerTube.clearAuthData()
        loadAuthState()
        // OAuth login debe reflejarse en UI aunque no haya cookies (tu log: oauth ok pero sale como guest)
        NotificationCenter.default.publisher(for: NSNotification.Name("OAuthAuthChanged"))
            .sink { [weak self] _ in self?.refreshAuthState() }
            .store(in: &cancellables)
    }

    // MARK: - Authentication State

    private func loadAuthState() {
        refreshAuthState()
    }

    func refreshAuthState() {
        isAuthenticated = innerTube.isAuthenticated

        if isAuthenticated {
            accountName = UserDefaults.standard.string(forKey: "accountName") ?? (OAuthManager.isAuthenticatedSync ? "YouTube (OAuth)" : nil)
            accountEmail = UserDefaults.standard.string(forKey: "accountEmail")
            accountImageUrl = UserDefaults.standard.string(forKey: "accountImageUrl")
        } else {
            // No limpiar nombre aquí, solo estado
        }
    }

    func saveAuthData(cookies: String, visitorData: String, dataSyncId: String, name: String?, email: String?, imageUrl: String? = nil) {
        innerTube.setAuthData(cookies: cookies, visitorData: visitorData, dataSyncId: dataSyncId)

        accountName = name
        accountEmail = email
        accountImageUrl = imageUrl

        UserDefaults.standard.set(name, forKey: "accountName")
        UserDefaults.standard.set(email, forKey: "accountEmail")
        UserDefaults.standard.set(imageUrl, forKey: "accountImageUrl")

        isAuthenticated = innerTube.isAuthenticated
        Task { await MainActor.run { DebugLogger.shared.log("🔐 saveAuthData isAuth=\(self.isAuthenticated) \(self.innerTube.debugAuthState) cookiesLen=\(cookies.count) visitorLen=\(visitorData.count) dataSyncLen=\(dataSyncId.count)") } }
        dlog("🔐 [Auth] saveAuthData isAuthenticated=\(isAuthenticated) \(innerTube.debugAuthState)")
    }

    func signOut() {
        innerTube.clearAuthData()
        OAuthManager.shared.signOut()

        accountName = nil
        accountEmail = nil
        accountImageUrl = nil

        UserDefaults.standard.removeObject(forKey: "accountName")
        UserDefaults.standard.removeObject(forKey: "accountEmail")
        UserDefaults.standard.removeObject(forKey: "accountImageUrl")

        isAuthenticated = false

        // Clear cookies from web view
        clearWebViewCookies()
    }

    private func clearWebViewCookies() {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = Set([WKWebsiteDataTypeCookies])

        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
            let youtubeRecords = records.filter { $0.displayName.contains("youtube") || $0.displayName.contains("google") }
            dataStore.removeData(ofTypes: dataTypes, for: youtubeRecords) {}
        }
    }

    // MARK: - Helper Methods

    func extractVisitorData(from webView: WKWebView) async throws -> String {
        let script = """
        (function() {
            try {
                const ytcfg = window.ytcfg;
                if (ytcfg && ytcfg.data_) {
                    return ytcfg.data_.VISITOR_DATA || ytcfg.data_.visitorData;
                }
                return null;
            } catch (e) {
                return null;
            }
        })()
        """

        if let result = try? await webView.evaluateJavaScript(script) as? String {
            return result
        }

        throw AuthenticationError.visitorDataNotFound
    }

    func extractDataSyncId(from webView: WKWebView) async throws -> String {
        let script = """
        (function() {
            try {
                const ytcfg = window.ytcfg;
                if (ytcfg && ytcfg.data_) {
                    return ytcfg.data_.DATASYNC_ID;
                }
                return null;
            } catch (e) {
                return null;
            }
        })()
        """

        if let result = try? await webView.evaluateJavaScript(script) as? String {
            // Clean up dataSyncId by removing trailing || or |
            let cleaned = result.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            return cleaned
        }

        throw AuthenticationError.dataSyncIdNotFound
    }

    func extractAccountInfo(from webView: WKWebView) async throws -> (name: String?, email: String?) {
        let script = """
        (function() {
            try {
                const ytcfg = window.ytcfg;
                if (ytcfg && ytcfg.data_) {
                    const name = ytcfg.data_.ACCOUNT_NAME;
                    const email = ytcfg.data_.ACCOUNT_EMAIL;
                    return JSON.stringify({ name: name, email: email });
                }
                return null;
            } catch (e) {
                return null;
            }
        })()
        """

        if let result = try? await webView.evaluateJavaScript(script) as? String,
           let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            return (json["name"], json["email"])
        }

        return (nil, nil)
    }

    func getCookies() async -> String {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        // Filter YouTube/Google cookies
        let youtubeCookies = cookies.filter { cookie in
            cookie.domain.contains("youtube.com") || cookie.domain.contains("google.com")
        }

        // Format as cookie header string
        return youtubeCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

enum AuthenticationError: Error {
    case visitorDataNotFound
    case dataSyncIdNotFound
    case cookiesNotFound
    case loginCancelled
    case loginFailed
}
