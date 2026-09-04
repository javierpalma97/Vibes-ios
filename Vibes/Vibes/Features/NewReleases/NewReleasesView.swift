import SwiftUI

struct NewReleasesView: View {
    @State private var albums: [YTAlbum] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let ytMusic = YouTubeMusic.shared

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.house")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    Text(error)
                        .foregroundColor(.secondary)

                    Button("Retry") {
                        Task {
                            await loadNewReleases()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(albums.indices, id: \.self) { index in
                        NavigationLink(destination: AlbumDetailView(album: albums[index])) {
                            NewReleaseAlbumCard(album: albums[index])
                        }
                    }
                }
                .padding()
            }

            Spacer(minLength: 120)
        }
        .navigationTitle("New Releases")
        .task {
            await loadNewReleases()
        }
    }

    private func loadNewReleases() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetchedAlbums = try await ytMusic.getNewReleases()
            await MainActor.run {
                albums = fetchedAlbums
            }
        } catch {
            dlog("❌ [NewReleases] Error loading new releases: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load new releases"
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }
}

// MARK: - New Release Album Card

struct NewReleaseAlbumCard: View {
    let album: YTAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: URL(string: album.thumbnailUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .aspectRatio(1, contentMode: .fit)
            .cornerRadius(12)

            Text(album.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)

            Text(album.artists)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let year = album.year {
                Text(year)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
