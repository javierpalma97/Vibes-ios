import SwiftUI
import WebKit

// Web session login (music.youtube.com) to capture Cookie + visitorData.
// Required for cloud mutations: the official web client authenticates like and
// playlist edits with SAPISIDHASH, which needs YouTube cookies. OAuth (device
// flow) stays for library reads and playback identity.
struct CookieLoginView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var holder = WebViewHolder()
    @State private var isSaving = false
    @State private var error: String?
    var onDone: () -> Void = {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Inicia sesión con tu cuenta de YouTube y pulsa Finalizar. Solo se usa para Me gusta y sincronizar playlists.")
                    .font(.caption)
                    .foregroundColor(VibesColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                MusicWebView(webView: holder.webView)

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                Button(isSaving ? "Guardando..." : "Finalizar") {
                    Task { await finish() }
                }
                .buttonStyle(.borderedProminent)
                .tint(VibesColors.accent)
                .foregroundColor(.black)
                .disabled(isSaving)
                .padding()
            }
            .vibesBackground()
            .navigationTitle("Sesión web de YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .foregroundColor(VibesColors.textPrimary)
                }
            }
        }
        .onAppear {
            if holder.webView.url == nil,
               let url = URL(string: "https://music.youtube.com") {
                holder.webView.load(URLRequest(url: url))
            }
        }
    }

    private func finish() async {
        isSaving = true
        error = nil
        defer { isSaving = false }

        let webView = holder.webView
        let cookies = await authManager.getCookies()
        guard cookies.contains("SAPISID") || cookies.contains("__Secure-3PAPISID")
                || cookies.contains("__Secure-3PSID") || cookies.contains("APISID") else {
            await MainActor.run {
                self.error = "No se encontró ninguna sesión: inicia sesión en la web primero."
            }
            return
        }

        do {
            let visitor = try await authManager.extractVisitorData(from: webView)
            let dataSyncId = (try? await authManager.extractDataSyncId(from: webView)) ?? ""
            let info: (name: String?, email: String?) = (try? await authManager.extractAccountInfo(from: webView)) ?? (nil, nil)
            await MainActor.run {
                authManager.saveAuthData(
                    cookies: cookies,
                    visitorData: visitor,
                    dataSyncId: dataSyncId,
                    name: info.name,
                    email: info.email
                )
                dlog("✅ [Auth] Web session connected")
                onDone()
            }
        } catch {
            await MainActor.run {
                self.error = "No se pudo leer la sesión (\(error.localizedDescription))."
            }
            dlog("❌ [Auth] Cookie login failed: \(error)")
        }
    }
}

final class WebViewHolder: ObservableObject {
    let webView: WKWebView = {
        let webView = WKWebView()
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6 Mobile/15E148 Safari/604.1"
        return webView
    }()
}

struct MusicWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
