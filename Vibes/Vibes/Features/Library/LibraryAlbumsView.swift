import SwiftUI
import SwiftData

struct LibraryAlbumsView: View {
    @Query(sort: \Album.dateAdded, order: .reverse) private var albums: [Album]

    var body: some View {
        ScrollView {
            if albums.isEmpty {
                VibesEmptyState(
                    icon: "square.stack",
                    title: "No albums in library",
                    subtitle: "Play albums to add them to your library"
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 16) {
                    ForEach(albums) { album in
                        NavigationLink(destination: AlbumDetailView(album: album.toYTAlbum())) {
                            VibesPlaylistCard(
                                title: album.title,
                                subtitle: album.artistsText ?? "",
                                artworkUrl: album.thumbnailUrl,
                                width: 160
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            Spacer(minLength: 140)
        }
        .vibesBackground()
        .navigationTitle("Albums")
    }
}
