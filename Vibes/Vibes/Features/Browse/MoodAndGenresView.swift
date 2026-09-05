import SwiftUI

struct MoodAndGenresView: View {
    @State private var sections: [MoodSection] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let ytMusic = YouTubeMusic.shared

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Estados de ánimo y géneros")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(VibesColors.textPrimary)
                .padding(.horizontal)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(VibesColors.textSecondary)

                    Text(error)
                        .foregroundColor(VibesColors.textSecondary)

                    Button("Reintentar") {
                        Task {
                            await loadGenres()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(VibesColors.textPrimary)
                            .padding(.horizontal)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(section.items) { genre in
                                NavigationLink(destination: BrowseView(browseId: genre.browseId, params: genre.params, title: genre.title)) {
                                    GenreCard(genre: genre)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .task {
            await loadGenres()
        }
    }

    private func loadGenres() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetchedSections = try await ytMusic.getMoodAndGenreSections()
            await MainActor.run {
                sections = fetchedSections
            }
        } catch {
            dlog("❌ [Genres] Error loading mood & genres: \(error)")
            await MainActor.run {
                errorMessage = "Error al cargar géneros y estados de ánimo"
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }
}

struct GenreCard: View {
    let genre: MoodAndGenre

    var body: some View {
        Text(genre.title)
            .font(.headline)
            .fontWeight(.medium)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
    }
}
