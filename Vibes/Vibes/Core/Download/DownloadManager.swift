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
        return FileManager.default.fileExists(atPath: fileURL.path)
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
        guard activeDownloads[song.id] == nil else { return }

        activeDownloads[song.id] = .downloading(progress: 0)

        do {
            // Get stream URL with content length
            let (streamUrl, contentLength) = try await ytMusic.getStreamUrlForDownload(videoId: song.id)

            guard let url = URL(string: streamUrl) else {
                throw DownloadError.invalidURL
            }

            // Create download request with headers
            var request = URLRequest(url: url)
            request.setValue("com.google.android.apps.youtube.music/7.51.52 (Linux; U; Android 13)", forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

            // Start download task
            let task = urlSession.downloadTask(with: request)
            task.taskDescription = song.id
            downloadTasks[song.id] = task
            task.resume()

        } catch {
            activeDownloads[song.id] = .failed(error: error.localizedDescription)
        }
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
        // Check which files exist in downloads directory
        if let files = try? FileManager.default.contentsOfDirectory(atPath: downloadsDirectory.path) {
            for file in files {
                if file.hasSuffix(".m4a") {
                    let songId = String(file.dropLast(4))
                    activeDownloads[songId] = .downloaded
                }
            }
        }
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
    case saveFailed
}
