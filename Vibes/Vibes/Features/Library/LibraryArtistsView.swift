import SwiftUI
import SwiftData

struct LibraryArtistsView: View {
    @Query(sort: \Artist.dateAdded, order: .reverse) private var artists: [Artist]

    var body: some View {
        ScrollView {
            if artists.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No artists in library")
                        .font(.headline)

                    Text("Play artists to add them to your library")
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
                    ForEach(artists) { artist in
                        NavigationLink(destination: ArtistDetailView(artist: artist.toYTArtist())) {
                            VStack(spacing: 8) {
                                AsyncImage(url: URL(string: artist.thumbnailUrl ?? "")) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                }
                                .frame(width: (UIScreen.main.bounds.width - 48) / 2, height: (UIScreen.main.bounds.width - 48) / 2)
                                .clipShape(Circle())

                                Text(artist.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Artists")
    }
}
