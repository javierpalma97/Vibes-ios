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
            VStack(alignment: .leading, spacing: 16) {
                Text("Novedades")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(VibesColors.textPrimary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let error = errorMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.largeTitle)
                            .foregroundColor(VibesColors.textTertiary)

                        Text(error)
                            .foregroundColor(VibesColors.textSecondary)

                        Button("Reintentar") {
                            Task {
                                await loadNewReleases()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VibesColors.accent)
                        .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if albums.isEmpty {
                    VibesEmptyState(icon: "sparkles", title: "Sin novedades")
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(albums.indices, id: \.self) { index in
                            NavigationLink(destination: AlbumDetailView(album: albums[index])) {
                                NewReleaseAlbumCard(album: albums[index])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            Spacer(minLength: 140)
        }
        .vibesBackground()
        .navigationTitle("Novedades")
        .navigationBarTitleDisplayMode(.large)
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
                errorMessage = "No se pudieron cargar las novedades"
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
            VibesArtwork(url: album.thumbnailUrl, size: 160, radius: 14)
                .frame(maxWidth: .infinity)

            Text(album.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(VibesColors.textPrimary)
                .lineLimit(2)

            Text(album.artists)
                .font(.caption)
                .foregroundColor(VibesColors.textSecondary)
                .lineLimit(1)

            if let year = album.year {
                Text(year)
                    .font(.caption2)
                    .foregroundColor(VibesColors.textTertiary)
            }
        }
    }
}
