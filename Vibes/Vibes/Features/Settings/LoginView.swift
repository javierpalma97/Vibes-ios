import SwiftUI
import AuthenticationServices

// Login: OAuth2 device flow (library reads) + optional web session
// (music.youtube.com cookies, required for cloud mutations: like, playlists).
struct LoginView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var oauth = OAuthManager.shared

    var body: some View {
        NavigationStack {
            OAuthLoginContent(onDone: { dismiss() })
                .vibesBackground()
                .navigationTitle("Sign in to YouTube Music")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") {
                            dismiss()
                        }
                        .foregroundColor(VibesColors.textPrimary)
                    }
                }
        }
    }
}

struct OAuthLoginContent: View {
    @StateObject private var oauth = OAuthManager.shared
    @State private var device: OAuthManager.DeviceCodeResponse?
    @State private var isPolling = false
    @State private var error: String?
    @State private var showImporter = false
    @State private var showCookieLogin = false
    var onDone: () -> Void = {}

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 56))
                .foregroundColor(VibesColors.accent)

            if oauth.isAuthenticated {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text("Conectado con OAuth2")
                        .font(.headline)
                        .foregroundColor(VibesColors.textPrimary)
                    if let token = oauth.accessToken {
                        Text("Token: \(token.prefix(20))...")
                            .font(.caption)
                            .foregroundColor(VibesColors.textSecondary)
                    }
                    Text("Puedes reproducir música y sincronizar tu biblioteca.")
                        .font(.caption)
                        .foregroundColor(VibesColors.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Conectar sesión web (Me gusta y playlists)") {
                        showCookieLogin = true
                    }
                    .font(.caption)
                    .foregroundColor(VibesColors.accent)
                    .padding(.top, 4)
                    Button("Cerrar sesión", role: .destructive) {
                        oauth.signOut()
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
                .padding()
            } else if let d = device {
                VStack(spacing: 12) {
                    Text("Abre esta página")
                        .font(.caption)
                        .foregroundColor(VibesColors.textSecondary)
                    Link(d.verification_url, destination: URL(string: d.verification_url)!)
                        .font(.headline)
                        .foregroundColor(VibesColors.accent)
                    Text("e introduce el código:")
                        .font(.caption)
                        .foregroundColor(VibesColors.textSecondary)
                    Text(d.user_code)
                        .font(.system(.largeTitle, design: .monospaced))
                        .bold()
                        .foregroundColor(VibesColors.textPrimary)
                        .textSelection(.enabled)
                        .padding()
                        .background(VibesColors.elevated)
                        .cornerRadius(12)
                    if let qr = d.verification_url_qr {
                        Link("QR", destination: URL(string: qr)!)
                            .foregroundColor(VibesColors.accent)
                    }
                    if isPolling {
                        ProgressView("Esperando confirmación…")
                            .foregroundColor(VibesColors.textSecondary)
                            .padding(.top)
                        Text("Expira en \(d.expires_in / 60) min")
                            .font(.caption2)
                            .foregroundColor(VibesColors.textSecondary)
                    }
                    Text("Por seguridad, considera usar una cuenta secundaria.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.top)
                }
                .padding()
            } else {
                VStack(spacing: 12) {
                    Text("Acceso con YouTube OAuth2")
                        .font(.headline)
                        .foregroundColor(VibesColors.textPrimary)
                    Text("Abre el enlace en otro dispositivo y autoriza. Ninguna contraseña sale de tu dispositivo.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(VibesColors.textSecondary)
                        .padding(.horizontal)
                    if let err = error {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    Button("Obtener código") {
                        Task { await start() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VibesColors.accent)
                    .foregroundColor(.black)
                    .disabled(isPolling)
                    Divider().padding(.vertical, 4)
                    Button("Importar oauth.json (ytmusicapi)") {
                        showImporter = true
                    }
                    .font(.caption)
                    .foregroundColor(VibesColors.accent)
                    Text("En el PC: pip install ytmusicapi && ytmusicapi oauth, y comparte aquí el oauth.json")
                        .font(.caption2)
                        .foregroundColor(VibesColors.textSecondary)
                        .multilineTextAlignment(.center)
                    Divider().padding(.vertical, 4)
                    Button("Conectar sesión web (Me gusta y playlists)") {
                        showCookieLogin = true
                    }
                    .font(.caption)
                    .foregroundColor(VibesColors.accent)
                }
                .padding()
            }

            Spacer()

            if !oauth.isAuthenticated && device != nil {
                Button("Cancelar") { device = nil; isPolling = false }
                    .foregroundColor(VibesColors.textSecondary)
            }
        }
        .task { if device == nil && !oauth.isAuthenticated { await start() } }
        .sheet(isPresented: $showCookieLogin) {
            CookieLoginView(onDone: { showCookieLogin = false; onDone() })
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    do {
                        let data = try Data(contentsOf: url)
                        try await OAuthManager.shared.importOAuthJson(data: data)
                        onDone()
                    } catch {
                        self.error = error.localizedDescription
                        dlog("❌ OAuth import \(error.localizedDescription)")
                    }
                }
            case .failure(let e): self.error = e.localizedDescription
            }
        }
    }

    private func start() async {
        isPolling = false; error = nil
        do {
            let d = try await oauth.startDeviceFlow()
            device = d; isPolling = true
            UIPasteboard.general.string = d.user_code
            if let url = URL(string: d.verification_url) { await UIApplication.shared.open(url) }
            let _ = try await oauth.pollForToken(deviceCode: d.device_code, interval: d.interval)
            isPolling = false
            try? await Task.sleep(nanoseconds: 500_000_000)
            onDone()
        } catch {
            isPolling = false
            self.error = error.localizedDescription
            dlog("❌ OAuth \(error.localizedDescription)")
        }
    }
}
