import SwiftUI
import SwiftData

// MARK: - Liked Songs Playlist

struct LikedSongsPlaylistView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            playlistHeaderSection
            songsListSection
        }
        .scrollContentBackground(.hidden)
        .vibesBackground()
        .navigationTitle("Liked Songs")
    }

    private var playlistHeaderSection: some View {
        Section {
            HStack(spacing: 16) {
                    Button(action: {
                        Task {
                            await queueManager.setQueue(libraryManager.likedSongs, enableRadio: false)
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Reproducir")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(libraryManager.likedSongs.isEmpty)

                    Button(action: {
                        Task {
                            await queueManager.setQueue(libraryManager.likedSongs.shuffled(), enableRadio: false)
                        }
                    }) {
                        HStack {
                            Image(systemName: "shuffle")
                            Text("Aleatorio")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                    .disabled(libraryManager.likedSongs.isEmpty)
                }
                .buttonStyle(PlainButtonStyle())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                // Download All button
                Button(action: {
                    Task {
                        await DownloadManager.shared.downloadMultiple(songs: libraryManager.likedSongs)
                    }
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                        Text("Descargar todo")
                        Spacer()
                    }
                    .foregroundColor(.accentColor)
                }
                .disabled(libraryManager.likedSongs.isEmpty)
        }
    }

    private var songsListSection: some View {
        Section(header: Text("\(libraryManager.likedSongs.count) songs")) {
                if libraryManager.likedSongs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("Sin me gustas")
                            .font(.headline)

                        Text("Marca Me gusta para verlas aquí")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(libraryManager.likedSongs) { song in
                        Button(action: {
                            Task {
                                await queueManager.setQueue(libraryManager.likedSongs, startIndex: libraryManager.likedSongs.firstIndex(where: { $0.id == song.id }) ?? 0, enableRadio: false)
                            }
                        }) {
                            SongRow(song: song)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                song.liked = false
                                song.dateModified = Date()
                                try? modelContext.save()
                            } label: {
                                Label("Unlike", systemImage: "heart.slash")
                            }
                            .tint(.gray)
                        }
                        .songContextMenu(song: song)
                    }
                }
        }
    }
}

// MARK: - Top Songs Playlist

struct TopSongsPlaylistView: View {
    @EnvironmentObject var queueManager: QueueManager
    @Environment(\.modelContext) private var modelContext

    @State private var topSongs: [Song] = []

    var body: some View {
        List {
            // Playlist header with actions
            Section {
                HStack(spacing: 16) {
                    Button(action: {
                        Task {
                            await queueManager.setQueue(topSongs, enableRadio: false)
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Reproducir")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(topSongs.isEmpty)

                    Button(action: {
                        Task {
                            await queueManager.setQueue(topSongs.shuffled(), enableRadio: false)
                        }
                    }) {
                        HStack {
                            Image(systemName: "shuffle")
                            Text("Aleatorio")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                    .disabled(topSongs.isEmpty)
                }
                .buttonStyle(PlainButtonStyle())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                // Download All button
                Button(action: {
                    Task {
                        await DownloadManager.shared.downloadMultiple(songs: topSongs)
                    }
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                        Text("Descargar todo")
                        Spacer()
                    }
                    .foregroundColor(.accentColor)
                }
                .disabled(topSongs.isEmpty)
            }

            // Songs list
            Section(header: Text("\(topSongs.count) songs")) {
                if topSongs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("Sin top de canciones")
                            .font(.headline)

                        Text("Reproduce para ver tus más escuchadas")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(topSongs.enumerated()), id: \.element.id) { index, song in
                        Button(action: {
                            Task {
                                await queueManager.setQueue(topSongs, startIndex: index, enableRadio: false)
                            }
                        }) {
                            HStack(spacing: 12) {
                                // Rank number
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, alignment: .leading)

                                SongRow(song: song)
                            }
                        }
                        .songContextMenu(song: song)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .vibesBackground()
        .navigationTitle("Top Songs")
        .task {
            await loadTopSongs()
        }
    }

    private func loadTopSongs() async {
        // Get play events from all time
        let eventDescriptor = FetchDescriptor<PlayEvent>()

        guard let events = try? modelContext.fetch(eventDescriptor) else {
            return
        }

        // Group by songId and calculate total play time
        var songPlayTimes: [String: Int64] = [:]
        for event in events {
            songPlayTimes[event.songId, default: 0] += event.playTime
        }

        // Get songs and sort by play time
        var songsWithPlayTime: [(song: Song, playTime: Int64)] = []
        for (songId, playTime) in songPlayTimes {
            let songDescriptor = FetchDescriptor<Song>(
                predicate: #Predicate { $0.id == songId }
            )
            if let songs = try? modelContext.fetch(songDescriptor),
               let song = songs.first {
                songsWithPlayTime.append((song: song, playTime: playTime))
            }
        }

        // Sort by play time DESC and take top 100
        topSongs = songsWithPlayTime
            .sorted { $0.playTime > $1.playTime }
            .prefix(100)
            .map { $0.song }
    }
}

// MARK: - Downloaded Songs Playlist

struct DownloadedPlaylistView: View {
    @EnvironmentObject var queueManager: QueueManager
    @Environment(\.modelContext) private var modelContext

    @State private var downloadedSongs: [Song] = []

    var body: some View {
        List {
            // Playlist header with actions
            Section {
                HStack(spacing: 16) {
                    Button(action: {
                        Task {
                            await queueManager.setQueue(downloadedSongs, enableRadio: false)
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Reproducir")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(downloadedSongs.isEmpty)

                    Button(action: {
                        Task {
                            await queueManager.setQueue(downloadedSongs.shuffled(), enableRadio: false)
                        }
                    }) {
                        HStack {
                            Image(systemName: "shuffle")
                            Text("Aleatorio")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                    .disabled(downloadedSongs.isEmpty)
                }
                .buttonStyle(PlainButtonStyle())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Songs list
            Section(header: Text("\(downloadedSongs.count) songs")) {
                if downloadedSongs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("Sin descargas")
                            .font(.headline)

                        Text("Descarga canciones para escuchar sin conexión")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(downloadedSongs) { song in
                        Button(action: {
                            Task {
                                await queueManager.setQueue(downloadedSongs, startIndex: downloadedSongs.firstIndex(where: { $0.id == song.id }) ?? 0, enableRadio: false)
                            }
                        }) {
                            SongRow(song: song)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task {
                                    await DownloadManager.shared.deleteDownload(songId: song.id)
                                    await loadDownloadedSongs()
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .songContextMenu(song: song)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .vibesBackground()
        .navigationTitle("Downloaded Songs")
        .task {
            await loadDownloadedSongs()
        }
    }

    private func loadDownloadedSongs() async {
        // Get all downloaded songs from DownloadManager
        let downloadedIds = DownloadManager.shared.getDownloadedSongIds()

        // Fetch songs from database
        let songDescriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { song in
                downloadedIds.contains(song.id)
            }
        )

        if let songs = try? modelContext.fetch(songDescriptor) {
            downloadedSongs = songs
        }
    }
}
