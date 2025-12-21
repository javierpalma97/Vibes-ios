import SwiftUI
import WebKit
import AuthenticationServices

struct LoginView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var isLoading: Bool = true
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var webView: WKWebView?

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
                print("🧭 [Login] Navigation to: \(url.absoluteString)")

                if url.host?.contains("accounts.google.com") == true {
                    hasVisitedGoogleAccounts = true
                    print("✅ [Login] Visiting Google OAuth page - this is where SAPISID should be set")
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url {
                print("🏁 [Login] Page finished loading: \(url.absoluteString)")

                // If we just finished loading Google accounts page, check for cookies
                if url.host?.contains("accounts.google.com") == true {
                    Task { @MainActor in
                        // Wait a bit for cookies to be set
                        try? await Task.sleep(nanoseconds: 2_000_000_000)

                        // Check if SAPISID cookie is now present
                        let cookies = await self.getCookies(from: webView)
                        let hasSAPISID = cookies.contains("SAPISID=")
                        print("🔍 [Login] After Google page load - Has SAPISID: \(hasSAPISID)")

                        if hasSAPISID {
                            print("✅ [Login] SAPISID captured from Google OAuth! Waiting for redirect back to YouTube Music...")
                        }
                    }
                }

                // If we've visited Google accounts and are back on YouTube Music, check login again
                if url.host?.contains("music.youtube.com") == true && hasVisitedGoogleAccounts && !hasCheckedLogin {
                    print("🔄 [Login] Back on YouTube Music after visiting Google - checking login again...")
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

                            print("🔐 [Login] Got auth data from JavaScript:")
                            print("  - VisitorData: \(visitorData.prefix(30))...")
                            print("  - DataSyncId: \(dataSyncId)")

                            // CRITICAL: Use WKWebView cookie store (like Android's CookieManager.getCookie())
                            // document.cookie CANNOT access HTTPOnly cookies like SAPISID
                            print("📦 [Login] Collecting ALL cookies from cookie store (including HTTPOnly)...")
                            let allCookies = await self.getCookies(from: webView)
                            print("  - Total cookies: \(allCookies.count) chars")
                            print("  - Cookie preview: \(allCookies.prefix(300))...")

                            // Check for SAPISID in the cookie string
                            let hasSAPISID = allCookies.contains("SAPISID=")
                            print("🔑 [Login] Has SAPISID cookie: \(hasSAPISID)")
                            print("🔍 [Login] Has visited Google accounts: \(hasVisitedGoogleAccounts)")

                            if !hasSAPISID && !hasVisitedGoogleAccounts {
                                print("⏳ [Login] No SAPISID yet and haven't visited Google OAuth - waiting for redirect...")
                                print("   Don't close dialog yet - OAuth redirect should happen soon")
                                // Don't mark as successful yet - wait for OAuth redirect
                                return
                            }

                            if !hasSAPISID && hasVisitedGoogleAccounts {
                                print("⚠️ [Login] SAPISID missing even after visiting accounts.google.com!")
                                print("   Waiting a bit longer for cookies to sync...")
                                // Wait and try again
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                let cookiesAfterWait = await self.getCookies(from: webView)
                                let hasSAPISIDNow = cookiesAfterWait.contains("SAPISID=")

                                if hasSAPISIDNow {
                                    print("✅ [Login] SAPISID appeared after waiting!")
                                    hasCheckedLogin = true
                                    parent.onLoginSuccess(cookiesAfterWait, visitorData, dataSyncId, accountName, accountEmail)
                                } else {
                                    print("❌ [Login] SAPISID still missing - OAuth cookies not being saved")
                                    print("   This is a WKWebView cookie storage issue")
                                }
                                return
                            }

                            if !allCookies.isEmpty && !visitorData.isEmpty && !dataSyncId.isEmpty && hasSAPISID {
                                hasCheckedLogin = true
                                print("✅ [Login] Authentication successful with SAPISID!")
                                parent.onLoginSuccess(allCookies, visitorData, dataSyncId, accountName, accountEmail)
                            } else {
                                print("❌ [Login] Missing required data")
                            }
                        } else {
                            print("ℹ️ [Login] User not logged in yet")
                            if let error = json["error"] as? String {
                                print("  Error: \(error)")
                            }
                        }
                    }
                } catch {
                    print("❌ [Login] Error checking login status: \(error)")
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

            print("🍪 [Login] Found \(allCookies.count) total cookies in WKWebView store")

            // CRITICAL: Only save YouTube domain cookies!
            // Android's CookieManager.getCookie("https://music.youtube.com") only returns
            // cookies for .youtube.com domain, NOT .google.com cookies
            // .google.com cookies are for accounts.google.com and shouldn't be sent to music.youtube.com
            let youtubeDomains = [".youtube.com", "youtube.com", "music.youtube.com"]
            let filteredCookies = allCookies.filter { cookie in
                youtubeDomains.contains { domain in
                    cookie.domain == domain || cookie.domain.hasSuffix(domain)
                }
            }

            print("🍪 [Login] Filtered to \(filteredCookies.count) YouTube-only cookies:")
            for cookie in filteredCookies {
                print("   - \(cookie.name) (domain: \(cookie.domain), httpOnly: \(cookie.isHTTPOnly))")
            }

            // Format as cookie header string (matching Android's format)
            return filteredCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
    }
}
