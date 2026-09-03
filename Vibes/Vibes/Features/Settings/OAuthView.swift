import SwiftUI

struct OAuthView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var oauth = OAuthManager.shared
    @State private var device: OAuthManager.DeviceCodeResponse?
    @State private var isPolling = false
    @State private var error: String?
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if oauth.isAuthenticated, let token = oauth.accessToken {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundColor(.green)
                        Text("Conectado con OAuth2").font(.headline)
                        Text("Token: \(token.prefix(20))...").font(.caption).foregroundColor(.secondary)
                        Text("Ya puedes reproducir y sincronizar librería sin depender de SAPISID.").font(.caption2).multilineTextAlignment(.center).foregroundColor(.secondary)
                        Button("Cerrar sesión OAuth", role: .destructive) {
                            oauth.signOut()
                        }.buttonStyle(.bordered)
                    }.padding()
                } else if let d = device {
                    VStack(spacing: 12) {
                        Text("Ve a").font(.caption).foregroundColor(.secondary)
                        Link(d.verification_url, destination: URL(string: d.verification_url)!)
                            .font(.headline)
                        Text("e introduce el código:").font(.caption).foregroundColor(.secondary)
                        Text(d.user_code).font(.system(.largeTitle, design: .monospaced)).bold().textSelection(.enabled).padding().background(Color.secondary.opacity(0.1)).cornerRadius(8)
                        if let qr = d.verification_url_qr { Link("QR", destination: URL(string: qr)!) }
                        if isPolling {
                            ProgressView("Esperando confirmación…").padding(.top)
                            Text("Intervalo \(d.interval)s – expira en \(d.expires_in/60) min").font(.caption2).foregroundColor(.secondary)
                        }
                        Text("Usa una cuenta burner como recomienda MusicBot #1670 – Google puede detectar cliente no oficial.").font(.caption2).foregroundColor(.orange).multilineTextAlignment(.center).padding(.top)
                    }.padding()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "tv").font(.largeTitle)
                        Text("Login YouTube OAuth2 (TV)").font(.headline)
                        Text("Alternativa a cookies. Abre el link en otro dispositivo y autoriza. No uses tu cuenta principal.").font(.caption).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
                        if let err = error { Text(err).font(.caption).foregroundColor(.red).padding(.horizontal) }
                        Button("Obtener código") {
                            Task { await start() }
                        }.buttonStyle(.borderedProminent).disabled(isPolling)
                        Divider().padding(.vertical, 4)
                        Button("Importar oauth.json (ytmusicapi)") {
                            showImporter = true
                        }.font(.caption)
                        Text("En PC: pip install ytmusicapi && ytmusicapi oauth → oauth.json → AirDrop aquí").font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }.padding()
                }
                Spacer()
                if !oauth.isAuthenticated && device != nil {
                    Button("Cancelar") { device = nil; isPolling = false }
                }
            }
            .navigationTitle("OAuth2 YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .task { if device == nil && !oauth.isAuthenticated { await start() } }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        do {
                            let data = try Data(contentsOf: url)
                            try await OAuthManager.shared.importOAuthJson(data: data)
                            dismiss()
                        } catch {
                            error = error.localizedDescription
                            DebugLogger.shared.log("❌ OAuth import \(error.localizedDescription)")
                        }
                    }
                case .failure(let e): error = e.localizedDescription
                }
            }
        }
    }

    private func start() async {
        isPolling = false; error = nil
        do {
            let d = try await oauth.startDeviceFlow()
            device = d; isPolling = true
            // copia automática al portapapeles
            UIPasteboard.general.string = d.user_code
            // abre el link
            if let url = URL(string: d.verification_url) { await UIApplication.shared.open(url) }
            let _ = try await oauth.pollForToken(deviceCode: d.device_code, interval: d.interval)
            isPolling = false
            // éxito -> cierra
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismiss()
        } catch {
            isPolling = false
            self.error = error.localizedDescription
            DebugLogger.shared.log("❌ OAuth \(error.localizedDescription)")
        }
    }
}
