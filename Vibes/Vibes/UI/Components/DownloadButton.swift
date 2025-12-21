import SwiftUI

struct DownloadButton: View {
    let song: Song
    @StateObject private var downloadManager = DownloadManager.shared

    var body: some View {
        Button(action: handleTap) {
            downloadIcon
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var downloadIcon: some View {
        switch downloadManager.downloadState(for: song.id) {
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .font(.title2)
                .foregroundColor(.secondary)

        case .downloading(let progress):
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 24, height: 24)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "stop.fill")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            }

        case .downloaded:
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundColor(.green)

        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.title2)
                .foregroundColor(.red)
        }
    }

    private func handleTap() {
        let state = downloadManager.downloadState(for: song.id)

        switch state {
        case .notDownloaded, .failed:
            Task {
                await downloadManager.download(song: song)
            }

        case .downloading:
            downloadManager.cancelDownload(songId: song.id)

        case .downloaded:
            // Show delete option
            break
        }
    }
}

// MARK: - Download Status View (for lists) - Now interactive!

struct DownloadStatusIndicator: View {
    let songId: String
    @StateObject private var downloadManager = DownloadManager.shared
    @EnvironmentObject var libraryManager: LibraryManager

    var body: some View {
        Button(action: handleTap) {
            statusView
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var statusView: some View {
        switch downloadManager.downloadState(for: songId) {
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .font(.title3)
                .foregroundColor(.secondary)

        case .downloading(let progress):
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 20, height: 20)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            }

        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(.green)

        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.title3)
                .foregroundColor(.red)
        }
    }

    private func handleTap() {
        let state = downloadManager.downloadState(for: songId)

        Task {
            switch state {
            case .notDownloaded, .failed:
                // Download the song
                if let song = await libraryManager.getSong(id: songId) {
                    await downloadManager.download(song: song)
                }

            case .downloading:
                // Cancel download
                downloadManager.cancelDownload(songId: songId)

            case .downloaded:
                // Delete download
                downloadManager.deleteDownload(songId: songId)
            }
        }
    }
}
