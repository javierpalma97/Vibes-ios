import SwiftUI

struct DebugLogView: View {
    @StateObject private var logger = DebugLogger.shared
    @State private var showShare = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Copiar", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = logger.fullLog
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Borrar", systemImage: "trash", role: .destructive) {
                    logger.clear()
                }
                .buttonStyle(.bordered)
                Button("Compartir", systemImage: "square.and.arrow.up") {
                    showShare = true
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                Text(logger.fullLog.isEmpty ? "Sin logs aún. Reproduce una canción sin descargar y vuelve aquí." : logger.fullLog)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .background(Color(UIColor.secondarySystemBackground))
        }
        .navigationTitle("Debug Log")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            if let data = logger.fullLog.data(using: .utf8) {
                ShareSheet(items: [data])
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
