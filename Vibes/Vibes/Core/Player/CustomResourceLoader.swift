import Foundation
import AVFoundation
import CommonCrypto

class CustomResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let userAgent: String

    private static let queue = DispatchQueue(label: "vibes.resourceLoader", qos: .userInitiated)
    private static var activeDownloads: [String: DownloadSession] = [:]

    private class DownloadSession {
        let url: URL
        let tempFile: URL
        var totalSize: Int64 = 0
        var downloadedSize: Int64 = 0
        var isComplete = false
        var error: Error?
        var isDownloading = false
        var pendingRequests: [(request: AVAssetResourceLoadingRequest, offset: Int64, length: Int)] = []
        var downloadTask: Task<Void, Never>?
        var authCookies: String?
        var consecutive403 = 0

        init(url: URL, tempFile: URL) {
            self.url = url
            self.tempFile = tempFile
        }
    }

    init(userAgent: String) {
        self.userAgent = userAgent
        super.init()
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url else {
            loadingRequest.finishLoading(with: NSError(domain: "CustomResourceLoader", code: -1))
            return false
        }

        var urlString = url.absoluteString
        if urlString.hasPrefix("customscheme://") {
            urlString = urlString.replacingOccurrences(of: "customscheme://", with: "https://")
        }
        guard let actualURL = URL(string: urlString) else {
            loadingRequest.finishLoading(with: NSError(domain: "CustomResourceLoader", code: -2))
            return false
        }

        let key = actualURL.absoluteString
        let session: DownloadSession

        if let existing = Self.activeDownloads[key] {
            session = existing
        } else {
            let hash = key.data(using: .utf8).map { sha256Hex($0) } ?? UUID().uuidString
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("vibes_stream_\(hash).m4a")
            session = DownloadSession(url: actualURL, tempFile: tempFile)
            Self.activeDownloads[key] = session
        }

        let offset = loadingRequest.dataRequest?.requestedOffset ?? 0
        let length = loadingRequest.dataRequest?.requestedLength ?? 0
        let isContentInfo = loadingRequest.contentInformationRequest != nil

        if isContentInfo {
            if session.totalSize > 0 {
                fillContentInfo(loadingRequest, session: session)
                loadingRequest.finishLoading()
                startDownloadIfNeeded(session)
                return true
            }
            session.pendingRequests.append((request: loadingRequest, offset: 0, length: 0))
            startDownloadIfNeeded(session)
            return true
        }

        if session.downloadedSize >= offset + Int64(length), length > 0 {
            if let data = readFromFile(session.tempFile, offset: offset, length: length) {
                loadingRequest.dataRequest?.respond(with: data)
                loadingRequest.finishLoading()
                return true
            }
        }

        if session.isComplete {
            if let data = readFromFile(session.tempFile, offset: offset, length: length) {
                loadingRequest.dataRequest?.respond(with: data)
                loadingRequest.finishLoading()
                return true
            }
            loadingRequest.finishLoading(with: session.error ?? NSError(domain: "CustomResourceLoader", code: -4))
            return true
        }

        session.pendingRequests.append((request: loadingRequest, offset: offset, length: length))
        startDownloadIfNeeded(session)
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        for (_, session) in Self.activeDownloads {
            session.pendingRequests.removeAll { $0.request == loadingRequest }
        }
    }

    private func fillContentInfo(_ request: AVAssetResourceLoadingRequest, session: DownloadSession) {
        guard let info = request.contentInformationRequest else { return }
        info.contentType = "public.mpeg-4-audio"
        if session.totalSize > 0 {
            info.contentLength = session.totalSize
        }
        info.isByteRangeAccessSupported = true
    }

    private func startDownloadIfNeeded(_ session: DownloadSession) {
        guard !session.isDownloading, !session.isComplete else { return }
        session.isDownloading = true

        // googlevideo valida la sesión por Cookie (no por SAPISIDHASH ni por UA):
        // se adjuntan SIEMPRE que haya login, venga del cliente que venga la URL.
        // Sin esto, las URLs emitidas en contexto autenticado mueren con 403 ~1MB.
        if let ck = InnerTubeClient.shared.currentCookies, !ck.isEmpty {
            session.authCookies = ck
        }

        session.downloadTask = Task { @MainActor in
            await performDownload(session)
        }
    }

    private func performDownload(_ session: DownloadSession) async {
        let chunkSize = 200_000
        var offset = 0

        while !Task.isCancelled {
            let end = offset + chunkSize - 1
            var request = URLRequest(url: session.url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
            if let ck = session.authCookies { request.setValue(ck, forHTTPHeaderField: "Cookie") }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw NSError(domain: "CustomResourceLoader", code: -1)
                }

                guard (200...299).contains(http.statusCode) || http.statusCode == 206 else {
                    if http.statusCode == 403 {
                        // La cuota por URL de googlevideo se agota (~1MB): reintentar la MISMA
                        // URL es inútil. Se reintenta 3 veces por si es transitorio y luego se
                        // falla la sesión para que PlayerManager pida una URL fresca (ya lo hace
                        // en su retry: playSong → getStreamUrl de nuevo).
                        session.consecutive403 += 1
                        await MainActor.run { DebugLogger.shared.log("⚠️ stream 403 at \(offset)/\(session.totalSize) intento \(session.consecutive403)/3 misma URL") }
                        if session.consecutive403 >= 3 {
                            session.error = NSError(domain: "CustomResourceLoader", code: 403,
                                userInfo: [NSLocalizedDescriptionKey: "googlevideo 403 persistente en offset \(offset): URL agotada, pedir fresca"])
                            break
                        }
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }
                    throw NSError(domain: "CustomResourceLoader", code: http.statusCode)
                }
                session.consecutive403 = 0

                if session.totalSize == 0 {
                    if let cr = http.value(forHTTPHeaderField: "Content-Range") {
                        let parts = cr.components(separatedBy: "/")
                        if parts.count == 2, let total = Int64(parts[1]) {
                            session.totalSize = total
                        }
                    }
                }

                if !FileManager.default.fileExists(atPath: session.tempFile.path) {
                    try data.write(to: session.tempFile)
                } else {
                    let fh = try FileHandle(forWritingTo: session.tempFile)
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }

                session.downloadedSize += Int64(data.count)

                if offset == 0, session.totalSize > 0 {
                    await MainActor.run { DebugLogger.shared.log("📥 stream pre-download start total=\(session.totalSize)") }
                }

                processPendingRequests(session)

                offset += data.count

                if offset % (chunkSize * 5) == 0, session.totalSize > 0 {
                    let pct = Int(Double(session.downloadedSize) / Double(session.totalSize) * 100)
                    await MainActor.run { DebugLogger.shared.log("📥 stream \(pct)% \(session.downloadedSize)/\(session.totalSize)") }
                }

                try? await Task.sleep(nanoseconds: 30_000_000)

                if data.count < chunkSize { break }
            } catch {
                if Task.isCancelled { break }
                session.error = error
                await MainActor.run { DebugLogger.shared.log("❌ stream download error at \(offset): \(error.localizedDescription)") }
                break
            }
        }

        session.isComplete = true
        session.isDownloading = false
        processPendingRequests(session)

        await MainActor.run {
            if let err = session.error {
                DebugLogger.shared.log("❌ stream pre-download FAILED \(session.downloadedSize)/\(session.totalSize): \(err.localizedDescription)")
            } else {
                DebugLogger.shared.log("✅ stream pre-download done \(session.downloadedSize)/\(session.totalSize) file=\(session.tempFile.lastPathComponent)")
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            try? FileManager.default.removeItem(at: session.tempFile)
            Self.activeDownloads.removeValue(forKey: session.url.absoluteString)
        }
    }

    private func processPendingRequests(_ session: DownloadSession) {
        var remaining: [(request: AVAssetResourceLoadingRequest, offset: Int64, length: Int)] = []

        for (req, offset, length) in session.pendingRequests {
            if let infoReq = req.contentInformationRequest, session.totalSize > 0 {
                fillContentInfo(req, session: session)
                req.finishLoading()
                continue
            }

            let availEnd = session.downloadedSize
            let reqEnd = offset + Int64(length)

            if session.isComplete || (length > 0 && availEnd >= reqEnd) || (session.isComplete && availEnd > offset) {
                let readLen = length > 0 ? length : Int(min(max(availEnd - offset, 0), Int64(chunkSize())))
                if let data = readFromFile(session.tempFile, offset: offset, length: readLen), !data.isEmpty {
                    req.dataRequest?.respond(with: data)
                    req.finishLoading()
                } else if let err = session.error {
                    // Sesión fallida (p.ej. 403 persistente): fallar la petición para que
                    // AVPlayer dispare el error y PlayerManager reintente con URL fresca
                    req.finishLoading(with: err)
                } else {
                    req.finishLoading()
                }
            } else {
                remaining.append((req, offset, length))
            }
        }

        session.pendingRequests = remaining
    }

    private func chunkSize() -> Int { 200_000 }

    private func readFromFile(_ fileURL: URL, offset: Int64, length: Int) -> Data? {
        guard let fh = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { fh.closeFile() }
        fh.seek(toFileOffset: UInt64(offset))
        if length > 0 {
            return fh.readData(ofLength: length)
        } else {
            return fh.readDataToEndOfFile()
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
        return digest.prefix(16).map { String(format: "%02hhx", $0) }.joined()
    }
}
