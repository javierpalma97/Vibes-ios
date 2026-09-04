import SwiftUI
import SwiftData

struct LibraryArtistsView: View {
    @Query(sort: \Artist.dateAdded, order: .reverse) private var artists: [Artist]

    var body: some View {
        ScrollView {
            if artists.isEmpty {
                VibesEmptyState(
                    icon: "person.2",
                    title: "No artists in library",
                    subtitle: "Play artists to add them to your library"
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 16) {
                    ForEach(artists) { artist in
                        NavigationLink(destination: ArtistDetailView(artist: artist.toYTArtist())) {
                            VStack(spacing: 8) {
                                AsyncImage(url: URL(string: artist.thumbnailUrl ?? "")) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .clipShape(Circle())
                                } placeholder: {
                                    Circle()
                                        .fill(VibesColors.elevated)
                                }
                                .frame(width: 140, height: 140)

                                Text(artist.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(VibesColors.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            Spacer(minLength: 140)
        }
        .vibesBackground()
        .navigationTitle("Artists")
    }
}
