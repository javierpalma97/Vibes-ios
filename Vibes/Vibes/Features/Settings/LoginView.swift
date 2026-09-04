import SwiftUI
import WebKit
import AuthenticationServices

struct LoginView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var oauth = OAuthManager.shared

    @State private var isLoading: Bool = true
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var webView: WKWebView?
    @State private var showOAuth = false

    var body: some View {
        NavigationStack {
            ZStack {
                WebViewRepresentable(
                    webView: $webView,
                    isLoading: $isLoading,
                    onLoginSuccess: { cookies, visitorData, dataSyncId, name, email in
                        authManager.saveAuthData(
                            cookies: cookies,
                            visitorData: visitorData,
                            dataSyncId: dataSyncId,
                            name: name,
                            email: email
                        )
                        dismiss()
                    },
                    onLoginError: { error in
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                )

                VStack {
                    Spacer()
                    // OAuth2 alternativa (MusicBot #1670) – no depende de SAPISID
                    Button {
                        showOAuth = true
                    } label: {
                        Label(oauth.isAuthenticated ? "OAuth: Conectado" : "Probar login OAuth2 (si cookies falla)", systemImage: "key.fill")
                            .font(.caption)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                    .padding(.bottom, 12)
                }

                if isLoading {
                    VStack {
                        ProgressView()
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Sign in to YouTube Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Login Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showOAuth) {
                OAuthView()
            }
        }
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool

    let onLoginSuccess: (String, String, String, String?, String?) -> Void
    let onLoginError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        // Use DEFAULT (persistent) data store like Android does
        // But clear all data first to force fresh OAuth
        let dataStore = WKWebsiteDataStore.default()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        // Store reference
        DispatchQueue.main.async {
            self.webView = webView
        }

        // Load YouTube Music with persistent store (cookies will be saved properly)
        Task {
            await MainActor.run {
                if let url = URL(string: "https://music.youtube.com") {
                    var request = URLRequest(url: url)
                    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                    webView.load(request)
                }
            }
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentable
        var hasCheckedLogin = false
        var isCheckingLogin = false
        var hasVisitedGoogleAccounts = false

        init(_ parent: WebViewRepresentable) {
            self.parent = parent
        }

        // Track ALL navigation to see if we visit accounts.google.com
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                dlog("🧭 [Login] Navigation to: \(url.absoluteString)")

                if url.host?.contains("accounts.google.com") == true {
                    hasVisitedGoogleAccounts = true
                    dlog("✅ [Login] Visiting Google OAuth page - this is where SAPISID should be set")
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url {
                dlog("🏁 [Login] Page finished loading: \(url.absoluteString)")

                // If we just finished loading Google accounts page, check for cookies
                if url.host?.contains("accounts.google.com") == true {
                    Task { @MainActor in
                        // Wait a bit for cookies to be set
                        try? await Task.sleep(nanoseconds: 2_000_000_000)

                        // Check if SAPISID cookie is now present
                        let cookies = await self.getCookies(from: webView)
                        let hasSAPISID = cookies.contains("SAPISID=")
                        dlog("🔍 [Login] After Google page load - Has SAPISID: \(hasSAPISID)")

                        if hasSAPISID {
                            dlog("✅ [Login] SAPISID captured from Google OAuth! Waiting for redirect back to YouTube Music...")
                        }
                    }
                }

                // If we've visited Google accounts and are back on YouTube Music, check login again
                if url.host?.contains("music.youtube.com") == true && hasVisitedGoogleAccounts && !hasCheckedLogin {
                    dlog("🔄 [Login] Back on YouTube Music after visiting Google - checking login again...")
                    // The normal login check will run and should now find SAPISID
                }
            }
            parent.isLoading = false

            // Match Android behavior - check on music.youtube.com pages only
            guard let url = webView.url,
                  url.absoluteString.hasPrefix("https://music.youtube.com"),
                  !hasCheckedLogin,
                  !isCheckingLogin else {
                return
            }

            // Check if user is logged in - matching Android's onPageFinished
            Task { @MainActor in
                isCheckingLogin = true
                defer { isCheckingLogin = false }

                do {
                    // Wait for JS to load - matching Android behavior
                    try await Task.sleep(nanoseconds: 2_000_000_000)

                    // Get VISITOR_DATA and DATASYNC_ID like Android does via JavaScript injection
                    let script = """
                    (function() {
                        try {
                            // Match Android's approach: window.yt.config_.VISITOR_DATA and DATASYNC_ID
                            const ytConfig = window.yt?.config_ || window.ytcfg?.data_;
                            if (!ytConfig) return JSON.stringify({ success: false, error: 'No yt config' });

                            const visitorData = ytConfig.VISITOR_DATA || ytConfig.visitorData;
                            const dataSyncId = ytConfig.DATASYNC_ID;
                            const accountName = ytConfig.ACCOUNT_NAME;
                            const accountEmail = ytConfig.ACCOUNT_EMAIL;

                            // Get ALL cookies like Android's CookieManager.getCookie()
                            const allCookies = document.cookie;

                            return JSON.stringify({
                                success: true,
                                visitorData: visitorData,
                                dataSyncId: dataSyncId,
                                accountName: accountName,
                                accountEmail: accountEmail,
                                cookies: allCookies,
                                isLoggedIn: !!dataSyncId
                            });
                        } catch (e) {
                            return JSON.stringify({ success: false, error: e.toString() });
                        }
                    })()
                    """

                    if let result = try? await webView.evaluateJavaScript(script) as? String,
                       let data = result.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                        if let success = json["success"] as? Bool, success,
                           let isLoggedIn = json["isLoggedIn"] as? Bool, isLoggedIn {

                            let visitorData = json["visitorData"] as? String ?? ""
                            let dataSyncId = json["dataSyncId"] as? String ?? ""
                            let accountName = json["accountName"] as? String
                            let accountEmail = json["accountEmail"] as? String

                            dlog("🔐 [Login] Got auth data from JavaScript:")
                            dlog("  - VisitorData: \(visitorData.prefix(30))...")
                            dlog("  - DataSyncId: \(dataSyncId)")

                            // CRITICAL: Use WKWebView cookie store (like Android's CookieManager.getCookie())
                            // document.cookie CANNOT access HTTPOnly cookies like SAPISID
                            dlog("📦 [Login] Collecting ALL cookies from cookie store (including HTTPOnly)...")
                            let allCookies = await self.getCookies(from: webView)
                            dlog("  - Total cookies: \(allCookies.count) chars")
                            dlog("  - Cookie preview: \(allCookies.prefix(300))...")

                            // Check for SAPISID in the cookie string
                            let hasSAPISID = allCookies.contains("SAPISID=")
                            dlog("🔑 [Login] Has SAPISID cookie: \(hasSAPISID)")
                            dlog("🔍 [Login] Has visited Google accounts: \(hasVisitedGoogleAccounts)")

                            if !hasSAPISID && !hasVisitedGoogleAccounts {
                                dlog("⏳ [Login] No SAPISID yet and haven't visited Google OAuth - waiting for redirect...")
                                dlog("   Don't close dialog yet - OAuth redirect should happen soon")
                                // Don't mark as successful yet - wait for OAuth redirect
                                return
                            }

                            if !hasSAPISID && hasVisitedGoogleAccounts {
                                dlog("⚠️ [Login] SAPISID missing even after visiting accounts.google.com!")
                                dlog("   Waiting a bit longer for cookies to sync...")
                                // Wait and try again
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                let cookiesAfterWait = await self.getCookies(from: webView)
                                let hasSAPISIDNow = cookiesAfterWait.contains("SAPISID=")

                                if hasSAPISIDNow {
                                    dlog("✅ [Login] SAPISID appeared after waiting!")
                                    hasCheckedLogin = true
                                    parent.onLoginSuccess(cookiesAfterWait, visitorData, dataSyncId, accountName, accountEmail)
                                } else {
                                    dlog("❌ [Login] SAPISID still missing - OAuth cookies not being saved")
                                    dlog("   This is a WKWebView cookie storage issue")
                                }
                                return
                            }

                            if !allCookies.isEmpty && !visitorData.isEmpty && !dataSyncId.isEmpty && hasSAPISID {
                                hasCheckedLogin = true
                                dlog("✅ [Login] Authentication successful with SAPISID!")
                                parent.onLoginSuccess(allCookies, visitorData, dataSyncId, accountName, accountEmail)
                            } else {
                                dlog("❌ [Login] Missing required data")
                            }
                        } else {
                            dlog("ℹ️ [Login] User not logged in yet")
                            if let error = json["error"] as? String {
                                dlog("  Error: \(error)")
                            }
                        }
                    }
                } catch {
                    dlog("❌ [Login] Error checking login status: \(error)")
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.onLoginError(error)
        }

        private func getCookies(from webView: WKWebView) async -> String {
            // Get ALL cookies from WKWebView cookie store (like Android's CookieManager)
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let allCookies = await withCheckedContinuation { continuation in
                cookieStore.getAllCookies { cookies in
                    continuation.resume(returning: cookies)
                }
            }

            dlog("🍪 [Login] Found \(allCookies.count) total cookies in WKWebView store")

            // Keep all YouTube + Google auth cookies (SAPISID lives on google.com for some accounts)
            // This fixes missing SAPISID leading to auth failures (Sync failed: vibes.innertubeError 0)
            let allowedDomains = [".youtube.com", "youtube.com", "music.youtube.com", ".google.com", "google.com", ".youtube-nocookie.com"]
            let filteredCookies = allCookies.filter { cookie in
                allowedDomains.contains { domain in
                    cookie.domain == domain || cookie.domain.hasSuffix(domain)
                }
            }

            // Fallback: if filtering yields no SAPISID, include all cookies (better than missing auth)
            var finalCookies = filteredCookies
            let hasSAPISID = filteredCookies.contains { $0.name == "SAPISID" || $0.name == "__Secure-3PAPISID" }
            if !hasSAPISID {
                dlog("⚠️ [Login] No SAPISID in filtered set, including all cookies as fallback")
                finalCookies = allCookies
            }

            dlog("🍪 [Login] Filtered to \(finalCookies.count) cookies:")
            for cookie in finalCookies {
                dlog("   - \(cookie.name) (domain: \(cookie.domain), httpOnly: \(cookie.isHTTPOnly))")
            }

            // Format as cookie header string (matching Android's format)
            return finalCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
    }
}
