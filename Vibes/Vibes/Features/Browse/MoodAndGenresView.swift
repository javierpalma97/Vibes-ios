import SwiftUI

struct MoodAndGenresView: View {
    @State private var genres: [MoodAndGenre] = []
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
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    Text(error)
                        .foregroundColor(.secondary)

                    Button("Retry") {
                        Task {
                            await loadGenres()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(genres) { genre in
                        NavigationLink(destination: BrowseView(browseId: genre.id, params: genre.params, title: genre.title)) {
                            GenreCard(genre: genre)
                        }
                    }
                }
                .padding()
            }

            Spacer(minLength: 120)
        }
        .navigationTitle("Mood & Genres")
        .task {
            await loadGenres()
        }
    }

    private func loadGenres() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetchedGenres = try await ytMusic.getMoodAndGenres()
            await MainActor.run {
                genres = fetchedGenres
            }
        } catch {
            print("❌ [Genres] Error loading mood & genres: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load mood & genres"
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
