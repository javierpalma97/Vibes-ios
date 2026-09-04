import SwiftUI
import SwiftData

struct LibrarySongsView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var queueManager: QueueManager
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Song.dateModified, order: .reverse) private var allSongs: [Song]

    @State private var songs: [Song] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if songs.isEmpty {
                    VibesEmptyState(
                        icon: "music.note",
                        title: "No songs in library",
                        subtitle: "Play songs to add them to your library"
                    )
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(songs) { song in
                            Button(action: {
                                Task {
                                    await queueManager.setQueue([song])
                                }
                            }) {
                                HStack(spacing: 12) {
                                    SongRow(song: song)
                                    Spacer()
                                    if song.liked {
                                        Image(systemName: "heart.fill")
                                            .foregroundColor(VibesColors.accent)
                                            .font(.caption)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(VibesColors.card)
                                .cornerRadius(VibesRadius.row)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
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
                Spacer(minLength: 140)
            }
            .padding(.top)
        }
        .vibesBackground()
        .navigationTitle("Songs")
        .onAppear {
            loadSongs()
        }
    }

    private func loadSongs() {
        songs = allSongs.filter { $0.playCount > 0 }
    }

    private func toggleLike(song: Song) {
        song.liked.toggle()
        song.dateModified = Date()
        try? modelContext.save()
    }
}
