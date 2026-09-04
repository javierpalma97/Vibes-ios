import Foundation
import Combine

enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(error: String)

    static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded): return true
        case (.downloaded, .downloaded): return true
        case (.downloading(let p1), .downloading(let p2)): return p1 == p2
        case (.failed(let e1), .failed(let e2)): return e1 == e2
        default: return false
        }
    }
}

@MainActor
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published var activeDownloads: [String: DownloadState] = [:]
    @Published var downloadQueue: [Song] = []

    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var urlSession: URLSession!
    private let ytMusic = YouTubeMusic.shared

    private override init() {
        super.init()

        // Use default (foreground) configuration for faster downloads
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.httpMaximumConnectionsPerHost = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.allowsExpensiveNetworkAccess = true          // Prefer speed over data saving
        config.allowsConstrainedNetworkAccess = true        // Allow Low Data Mode if user triggered
        config.waitsForConnectivity = false                 // Fail fast instead of stalling
        config.shouldUseExtendedBackgroundIdleMode = false  // Foreground-priority downloads

        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        // Load persisted download states asynchronously to avoid blocking startup
        Task { @MainActor in
            await loadDownloadStates()
        }
    }

    // MARK: - Download Directory

    var downloadsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let downloadsDir = paths[0].appendingPathComponent("Downloads", isDirectory: true)

        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: downloadsDir.path) {
            try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        }

        return downloadsDir
    }

    func localFileURL(for songId: String) -> URL {
        return downloadsDirectory.appendingPathComponent("\(songId).m4a")
    }

    // MARK: - Download State

    func isDownloaded(_ songId: String) -> Bool {
        let fileURL = localFileURL(for: songId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        // Ignore 0-byte files (failed downloads that left empty files) – matches "51 canciones ZERO KB" bug
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? UInt64, size < 1024 {
            // File is empty or too small – treat as not downloaded and clean up
            try? FileManager.default.removeItem(at: fileURL)
            return false
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? UInt64 {
            return size > 0
        }
        return true
    }

    func downloadState(for songId: String) -> DownloadState {
        if isDownloaded(songId) {
            return .downloaded
        }
        return activeDownloads[songId] ?? .notDownloaded
    }

    // MARK: - Download Actions

    func download(song: Song) async {
        guard !isDownloaded(song.id) else { return }
        // Prevent duplicate downloads – allow retry if previous failed
        if case .downloading = activeDownloads[song.id] { return }

        activeDownloads[song.id] = .downloading(progress: 0)

        do {
            // Get stream URL with content length and client type
            let (streamUrl, contentLength, clientType) = try await ytMusic.getStreamUrlForDownload(videoId: song.id)

            guard let url = URL(string: streamUrl) else {
                throw DownloadError.invalidURL
            }

            // Use chunked download via Range header (googlevideo rejects full &range query with 403)
            try await performChunkedDownload(songId: song.id, url: url, contentLength: contentLength, clientType: clientType)

        } catch {
            dlog("❌ [Download] Failed for \(song.id): \(error)")
            activeDownloads[song.id] = .failed(error: error.localizedDescription)
        }
    }

    private func performChunkedDownload(songId: String, url: URL, contentLength: Int64, clientType: InnerTubeClientType) async throws {
        var clientType = clientType
        let destinationURL = localFileURL(for: songId)
        let downloadsDir = destinationURL.deletingLastPathComponent()

        // Ensure directory exists
        if !FileManager.default.fileExists(atPath: downloadsDir.path) {
            try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        }
        // Remove any existing file
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: destinationURL) else {
            throw DownloadError.saveFailed
        }
        defer { try? fileHandle.close() }

        var totalLength = contentLength
        // If contentLength is 0/unknown, we'll discover it from first Content-Range response
        // Use 200KB chunks – 1MB triggers 403 after 400KB on IOS, 500KB fails, 200KB is safe for ANDROID 139
        let chunkSize: Int64 = 200_000

        var offset: Int64 = 0
        var totalWritten: Int64 = 0
        var discoveredLength: Int64?

        var rn = 0
        // First, if totalLength is 0, do a probe to discover length via Range 0-999999
        if totalLength <= 0 {
            let probeEnd: Int64 = chunkSize - 1
            let (probeData, probeTotal) = try await fetchChunk(url: url, clientType: clientType, start: 0, end: probeEnd, rn: rn); rn += 1
            if let total = probeTotal {
                totalLength = total
                discoveredLength = total
            } else {
                // Fallback: use probeData count as total if server returned 200 with small range (query style)
                // But our fetchChunk uses header Range, so probeTotal should be available via Content-Range
                totalLength = Int64(probeData.count)
            }
            try fileHandle.write(contentsOf: probeData)
            totalWritten += Int64(probeData.count)
            offset = Int64(probeData.count)
            await MainActor.run { self.activeDownloads[songId] = .downloading(progress: totalLength > 0 ? Double(totalWritten)/Double(totalLength) : 0.5) }
            dlog("📥 [Download] Probe \(songId): \(probeData.count) bytes, total \(totalLength)")
        }

        // If we still don't know totalLength, try to use contentLength from probe or fallback to streaming
        if totalLength <= 0 {
            totalLength = 10_000_000 // fallback estimate, will stop when server returns < chunkSize
        }

        var currentURL = url
        var urlRefreshes = 0
        let maxRefreshes = 15
        // Con URLs VISIONOS no hay muro: proactivo desactivado, solo reactivo ante 403
        let segmentSize: Int64 = 50_000_000
        var segmentStart: Int64 = 0
        while offset < totalLength {
            // Check for cancellation
            if Task.isCancelled { throw DownloadError.downloadFailed }

            if totalWritten - segmentStart >= segmentSize && urlRefreshes < maxRefreshes {
                do {
                    let (freshUrl, _, freshClient) = try await ytMusic.getStreamUrlForDownload(videoId: songId)
                    guard let fresh = URL(string: freshUrl) else { throw DownloadError.invalidURL }
                    currentURL = fresh
                    clientType = freshClient
                    segmentStart = totalWritten
                    rn = 0
                    urlRefreshes += 1
                    dlog("🔄 [Download] URL fresca proactiva (\(urlRefreshes)) en offset \(offset)")
                } catch {
                    dlog("⚠️ [Download] no se pudo refrescar URL, sigo con la actual: \(error)")
                }
            }

            let end = min(offset + chunkSize - 1, totalLength - 1)
            let chunkData: Data
            let chunkTotal: Int64?
            do {
                (chunkData, chunkTotal) = try await fetchChunk(url: currentURL, clientType: clientType, start: offset, end: end, rn: rn); rn += 1
            } catch DownloadError.forbidden where urlRefreshes < maxRefreshes {
                // Cuota de la URL agotada (~1MB): pedir URL fresca y reanudar mismo offset
                urlRefreshes += 1
                dlog("⚠️ [Download] 403 en offset \(offset), pidiendo URL fresca (\(urlRefreshes)/\(maxRefreshes))...")
                let (freshUrl, _, freshClient) = try await ytMusic.getStreamUrlForDownload(videoId: songId)
                guard let fresh = URL(string: freshUrl) else { throw DownloadError.invalidURL }
                currentURL = fresh
                clientType = freshClient
                segmentStart = totalWritten
                rn = 0
                continue
            }
            // If server gave us total via Content-Range and we hadn't known it, update
            if let ct = chunkTotal, discoveredLength == nil {
                totalLength = ct
            }
            try fileHandle.write(contentsOf: chunkData)
            totalWritten += Int64(chunkData.count)
            offset += Int64(chunkData.count)

            let progress = totalLength > 0 ? Double(totalWritten)/Double(totalLength) : 0.5
            await MainActor.run { self.activeDownloads[songId] = .downloading(progress: progress) }
            dlog("📥 [Download] \(songId) chunk \(offset)-\(end) \(chunkData.count) bytes progress \(Int(progress*100))%")

            // If server returned less than requested, we're at EOF
            if Int64(chunkData.count) < (end - offset + Int64(chunkData.count) + 1) && chunkData.count < chunkSize {
                // Heuristic: if chunk smaller than requested, might be last chunk
                if totalWritten >= totalLength || chunkData.count == 0 {
                    break
                }
            }
            // If we fetched less than chunkSize and totalWritten >= totalLength, break
            if chunkData.count < chunkSize && totalWritten >= totalLength {
                break
            }
        }

        // Validate final file size
        let attrs = try? FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let finalSize = attrs?[.size] as? UInt64 ?? 0
        dlog("✅ [Download] Completed \(songId) final size \(finalSize) bytes (expected \(totalLength))")
        if finalSize < 1024 {
            // File too small – likely failed (HTML error page or empty)
            try? FileManager.default.removeItem(at: destinationURL)
            throw DownloadError.downloadFailed
        }

        await MainActor.run {
            self.activeDownloads[songId] = .downloaded
            self.downloadTasks.removeValue(forKey: songId)
        }
    }

    private func fetchChunk(url: URL, clientType: InnerTubeClientType, start: Int64, end: Int64, rn: Int) async throws -> (Data, Int64?) {
        // rn incremental como ExoPlayer; sin él googlevideo 403 tras N rangos
        var reqURL = url
        if var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var items = c.queryItems ?? []
            items.removeAll { $0.name == "rn" }
            items.append(URLQueryItem(name: "rn", value: String(rn)))
            c.queryItems = items
            reqURL = c.url ?? url
        }
        var request = URLRequest(url: reqURL)
        request.setValue(InnerTubeClient.shared.getUserAgent(for: clientType), forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        // googlevideo valida sesión por Cookie: sin esto, URLs autenticadas → 403 ~1MB
        if let ck = InnerTubeClient.shared.currentCookies, !ck.isEmpty {
            request.setValue(ck, forHTTPHeaderField: "Cookie")
        }
        request.timeoutInterval = 30

        // Use shared session for chunk fetch (no delegate needed)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DownloadError.downloadFailed }

        // Accept 206 Partial Content or 200 OK (for small query range fallback)
        guard (200...299).contains(http.statusCode) || http.statusCode == 206 else {
            dlog("❌ [Download] Chunk \(start)-\(end) HTTP \(http.statusCode)")
            if let body = String(data: data, encoding: .utf8) {
                dlog("  body preview: \(body.prefix(500))")
            }
            if http.statusCode == 403 { throw DownloadError.forbidden }
            throw DownloadError.downloadFailed
        }

        // Try to parse total length from Content-Range: "bytes 0-999/1718053"
        var total: Int64? = nil
        if let cr = http.value(forHTTPHeaderField: "Content-Range") {
            let parts = cr.components(separatedBy: "/")
            if parts.count == 2, let t = Int64(parts[1]) {
                total = t
            }
        } else if let cl = http.value(forHTTPHeaderField: "Content-Length"), let len = Int64(cl) {
            // For 200 with Content-Length, if we requested 0-999, Content-Length will be 1000, not total
            // Use Content-Range if available, otherwise keep nil
        }

        return (data, total)
    }

    func cancelDownload(songId: String) {
        if let task = downloadTasks[songId] {
            task.cancel()
            downloadTasks.removeValue(forKey: songId)
        }
        activeDownloads.removeValue(forKey: songId)
    }

    func deleteDownload(songId: String) {
        let fileURL = localFileURL(for: songId)

        do {
            try FileManager.default.removeItem(at: fileURL)
            activeDownloads.removeValue(forKey: songId)
        } catch {
            // Silently fail
        }
    }

    func downloadMultiple(songs: [Song]) async {
        for song in songs {
            await download(song: song)
        }
    }

    // MARK: - Persistence

    private func loadDownloadStates() async {
        // Check which files exist in downloads directory – ignore 0-byte files (failed downloads)
        if let files = try? FileManager.default.contentsOfDirectory(atPath: downloadsDirectory.path) {
            for file in files {
                if file.hasSuffix(".m4a") {
                    let filePath = downloadsDirectory.appendingPathComponent(file).path
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
                       let size = attrs[.size] as? UInt64, size < 1024 {
                        // Remove empty/corrupt download (matches ZERO KB bug)
                        try? FileManager.default.removeItem(atPath: filePath)
                        dlog("🗑️ [Download] Removed empty file \(file) (\(size) bytes)")
                        continue
                    }
                    let songId = String(file.dropLast(4))
                    activeDownloads[songId] = .downloaded
                }
            }
        }
        // Log current state
        dlog("📥 [Download] Loaded \(activeDownloads.filter { $0.value == .downloaded }.count) downloaded, total size \(formattedDownloadSize)")
    }

    func saveDownloadStates() {
        // States are persisted via file system
    }

    // MARK: - Storage Info

    func getDownloadedSongIds() -> [String] {
        var songIds: [String] = []

        if let files = try? FileManager.default.contentsOfDirectory(atPath: downloadsDirectory.path) {
            for file in files {
                if file.hasSuffix(".m4a") {
                    let songId = String(file.dropLast(4))
                    songIds.append(songId)
                }
            }
        }

        return songIds
    }

    var totalDownloadSize: Int64 {
        var size: Int64 = 0

        if let files = try? FileManager.default.contentsOfDirectory(atPath: downloadsDirectory.path) {
            for file in files {
                let filePath = downloadsDirectory.appendingPathComponent(file).path
                if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
                   let fileSize = attrs[.size] as? Int64 {
                    size += fileSize
                }
            }
        }

        return size
    }

    var formattedDownloadSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalDownloadSize)
    }

    func deleteAllDownloads() {
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: downloadsDirectory.path)
            for file in files {
                let filePath = downloadsDirectory.appendingPathComponent(file)
                try FileManager.default.removeItem(at: filePath)
            }
            activeDownloads.removeAll()
        } catch {
            // Silently fail
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let songId = downloadTask.taskDescription else { return }

        let destinationURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("\(songId).m4a")

        let downloadsDir = destinationURL.deletingLastPathComponent()

        do {
            // Ensure Downloads directory exists
            if !FileManager.default.fileExists(atPath: downloadsDir.path) {
                try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true, attributes: nil)
            }

            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            // Move downloaded file
            try FileManager.default.moveItem(at: location, to: destinationURL)

            // Update state on main actor
            Task { @MainActor in
                self.activeDownloads[songId] = .downloaded
                self.downloadTasks.removeValue(forKey: songId)
            }

        } catch {
            Task { @MainActor in
                self.activeDownloads[songId] = .failed(error: error.localizedDescription)
                self.downloadTasks.removeValue(forKey: songId)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let songId = downloadTask.taskDescription else { return }

        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            progress = 0.5
        }

        Task { @MainActor in
            self.activeDownloads[songId] = .downloading(progress: progress)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let songId = downloadTask.taskDescription,
              let error = error else { return }

        Task { @MainActor in
            self.activeDownloads[songId] = .failed(error: error.localizedDescription)
            self.downloadTasks.removeValue(forKey: songId)
        }
    }
}

// MARK: - Download Error

enum DownloadError: Error {
    case invalidURL
    case downloadFailed
    case forbidden
    case saveFailed
}
