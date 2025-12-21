import SwiftUI
import SwiftData

struct LibraryAlbumsView: View {
    @Query(sort: \Album.dateAdded, order: .reverse) private var albums: [Album]

    var body: some View {
        ScrollView {
            if albums.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No albums in library")
                        .font(.headline)

                    Text("Play albums to add them to your library")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(albums) { album in
                        NavigationLink(destination: AlbumDetailView(album: album.toYTAlbum())) {
                            VStack(alignment: .leading, spacing: 8) {
                                AsyncImage(url: URL(string: album.thumbnailUrl ?? "")) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                }
                                .frame(width: (UIScreen.main.bounds.width - 48) / 2, height: (UIScreen.main.bounds.width - 48) / 2)
                                .cornerRadius(8)

                                Text(album.title)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                if let artist = album.artistsText {
                                    Text(artist)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Albums")
    }
}
