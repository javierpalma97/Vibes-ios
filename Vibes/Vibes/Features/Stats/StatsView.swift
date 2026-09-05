import SwiftUI
import SwiftData

struct StatsView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.modelContext) private var modelContext

    @State private var topSongs: [Song] = []
    @State private var topArtists: [(name: String, playTime: Int64)] = []
    @State private var totalPlayTime: TimeInterval = 0
    @State private var totalSongsPlayed: Int = 0
    @State private var isLoading = true
    @State private var timeRange: TimeRange = .allTime

    enum TimeRange: String, CaseIterable {
        case week = "This Week"
        case month = "This Month"
        case year = "This Year"
        case allTime = "All Time"

        var predicate: Date {
            let calendar = Calendar.current
            switch self {
            case .week: return calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            case .month: return calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            case .year: return calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
            case .allTime: return Date.distantPast
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Time Range Picker
                Picker("Time Range", selection: $timeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: timeRange) { _, _ in
                    Task { await loadStats() }
                }

                // Summary Cards
                HStack(spacing: 16) {
                    StatCard(
                        title: "Songs Played",
                        value: "\(totalSongsPlayed)",
                        icon: "music.note",
                        color: .blue
                    )

                    StatCard(
                        title: "Listen Time",
                        value: formatPlayTime(totalPlayTime),
                        icon: "clock.fill",
                        color: .purple
                    )
                }
                .padding(.horizontal)

                // Top Songs
                if !topSongs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Más escuchadas")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)

                        ForEach(topSongs.indices, id: \.self) { index in
                            TopSongRow(song: topSongs[index], rank: index + 1)
                        }
                    }
                }

                // Top Artists
                if !topArtists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Artistas populares")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)

                        ForEach(topArtists.indices, id: \.self) { index in
                            TopArtistRow(
                                name: topArtists[index].name,
                                playTime: topArtists[index].playTime,
                                rank: index + 1
                            )
                        }
                    }
                }

                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                }

                Spacer(minLength: 120)
            }
            .padding(.top)
        }
        .navigationTitle("Your Stats")
        .task {
            await loadStats()
        }
    }

    private func loadStats() async {
        isLoading = true

        // Get all PlayEvents within time range
        let startDate = timeRange.predicate
        let eventDescriptor = FetchDescriptor<PlayEvent>(
            predicate: #Predicate { $0.timestamp >= startDate }
        )

        guard let events = try? modelContext.fetch(eventDescriptor) else {
            isLoading = false
            return
        }

        // Aggregate by songId
        var songStats: [String: (playCount: Int, totalPlayTime: Int64)] = [:]
        for event in events {
            let current = songStats[event.songId, default: (0, 0)]
            songStats[event.songId] = (current.playCount + 1, current.totalPlayTime + event.playTime)
        }

        // Fetch songs in ONE query (fast! avoids N+1)
        let songIds = Array(songStats.keys)
        guard !songIds.isEmpty else {
            // No play events yet
            topSongs = []
            topArtists = []
            totalSongsPlayed = 0
            totalPlayTime = 0
            isLoading = false
            return
        }

        let songDescriptor = FetchDescriptor<Song>(
            predicate: #Predicate { songIds.contains($0.id) }
        )

        guard let songs = try? modelContext.fetch(songDescriptor) else {
            isLoading = false
            return
        }

        // Create lookup and sort by total playTime
        let songsWithStats = songs.compactMap { song -> (song: Song, stats: (playCount: Int, totalPlayTime: Int64))? in
            guard let stats = songStats[song.id] else { return nil }
            return (song: song, stats: stats)
        }.sorted { $0.stats.totalPlayTime > $1.stats.totalPlayTime }

        topSongs = Array(songsWithStats.prefix(10).map { $0.song })

        // Calculate totals
        totalSongsPlayed = Set(songStats.keys).count // Unique songs
        totalPlayTime = TimeInterval(songStats.values.reduce(0) { $0 + $1.totalPlayTime }) / 1000.0 // ms to seconds

        // Top artists by total playTime
        var artistStats: [String: Int64] = [:]
        for (song, stats) in songsWithStats {
            let artist = song.artistsText ?? "Unknown"
            artistStats[artist, default: 0] += stats.totalPlayTime
        }

        topArtists = artistStats
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { (name: $0.key, playTime: $0.value) }

        isLoading = false
    }

    private func formatPlayTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Top Song Row

struct TopSongRow: View {
    let song: Song
    let rank: Int
    @EnvironmentObject var queueManager: QueueManager

    var body: some View {
        Button(action: {
            Task {
                await queueManager.setQueue([song])
            }
        }) {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(width: 30)

                AsyncImage(url: URL(string: song.thumbnailUrl ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 48, height: 48)
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(song.artistsText ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if song.playCount > 0 {
                    Text("\(song.playCount) plays")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Top Artist Row

struct TopArtistRow: View {
    let name: String
    let playTime: Int64 // milliseconds
    let rank: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline)
                .foregroundColor(.secondary)
                .frame(width: 30)

            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 48, height: 48)
                .overlay(
                    Text(String(name.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundColor(.secondary)
                )

            Text(name)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(1)

            Spacer()

            Text(formatPlayTime(TimeInterval(playTime) / 1000.0))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func formatPlayTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
}
