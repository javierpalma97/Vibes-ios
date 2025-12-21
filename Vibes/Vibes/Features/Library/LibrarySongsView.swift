import SwiftUI
import SwiftData

struct LibrarySongsView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Song.dateModified, order: .reverse) private var allSongs: [Song]

    @State private var songs: [Song] = []

    var body: some View {
        List {
            if songs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No songs in library")
                        .font(.headline)

                    Text("Play songs to add them to your library")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .listRowBackground(Color.clear)
            } else {
                ForEach(songs) { song in
                    Button(action: {
                        Task {
                            await queueManager.setQueue([song])
                        }
                    }) {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: song.thumbnailUrl ?? "")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .frame(width: 50, height: 50)
                            .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Text(song.artistsText ?? "Unknown Artist")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if song.liked {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            toggleLike(song: song)
                        } label: {
                            Label(song.liked ? "Unlike" : "Like", systemImage: song.liked ? "heart.slash" : "heart")
                        }
                        .tint(song.liked ? .gray : .red)
                    }
                }
            }
        }
        .navigationTitle("Songs")
        .onAppear {
            loadSongs()
        }
    }

    private func loadSongs() {
        // Filter songs that have been played (in library)
        songs = allSongs.filter { $0.playCount > 0 }
    }

    private func toggleLike(song: Song) {
        song.liked.toggle()
        song.dateModified = Date()
        try? modelContext.save()
    }
}
