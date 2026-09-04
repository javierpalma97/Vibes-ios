import SwiftUI
import AuthenticationServices

// OAuth-only login (cookie/WebView login retired: SAPISID sessions are rejected
// by YouTube for private content; OAuth2 Bearer is the only working method).
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
                        Button("Cancel") {
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
                    Text("Connected with OAuth2")
                        .font(.headline)
                        .foregroundColor(VibesColors.textPrimary)
                    if let token = oauth.accessToken {
                        Text("Token: \(token.prefix(20))...")
                            .font(.caption)
                            .foregroundColor(VibesColors.textSecondary)
                    }
                    Text("You can play music and sync your library.")
                        .font(.caption)
                        .foregroundColor(VibesColors.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Sign Out", role: .destructive) {
                        oauth.signOut()
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
                .padding()
            } else if let d = device {
                VStack(spacing: 12) {
                    Text("Open this page")
                        .font(.caption)
                        .foregroundColor(VibesColors.textSecondary)
                    Link(d.verification_url, destination: URL(string: d.verification_url)!)
                        .font(.headline)
                        .foregroundColor(VibesColors.accent)
                    Text("and enter the code:")
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
                        ProgressView("Waiting for confirmation…")
                            .foregroundColor(VibesColors.textSecondary)
                            .padding(.top)
                        Text("Expires in \(d.expires_in / 60) min")
                            .font(.caption2)
                            .foregroundColor(VibesColors.textSecondary)
                    }
                    Text("For your security, consider a secondary YouTube account.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.top)
                }
                .padding()
            } else {
                VStack(spacing: 12) {
                    Text("YouTube OAuth2 Login")
                        .font(.headline)
                        .foregroundColor(VibesColors.textPrimary)
                    Text("Open the link on another device and authorize. No passwords leave your device.")
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
                    Button("Get Code") {
                        Task { await start() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VibesColors.accent)
                    .foregroundColor(.black)
                    .disabled(isPolling)
                    Divider().padding(.vertical, 4)
                    Button("Import oauth.json (ytmusicapi)") {
                        showImporter = true
                    }
                    .font(.caption)
                    .foregroundColor(VibesColors.accent)
                    Text("On PC: pip install ytmusicapi && ytmusicapi oauth, then share oauth.json here")
                        .font(.caption2)
                        .foregroundColor(VibesColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }

            Spacer()

            if !oauth.isAuthenticated && device != nil {
                Button("Cancel") { device = nil; isPolling = false }
                    .foregroundColor(VibesColors.textSecondary)
            }
        }
        .task { if device == nil && !oauth.isAuthenticated { await start() } }
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
