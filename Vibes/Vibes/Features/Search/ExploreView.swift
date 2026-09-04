import SwiftUI

struct ExploreView: View {
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Button(action: { showSearch = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(VibesColors.textSecondary)
                            Text("Search songs, artists, playlists...")
                                .foregroundColor(VibesColors.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(VibesColors.elevated)
                        .cornerRadius(VibesRadius.pill)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    VibesSectionHeader(title: "Browse", subtitle: "Charts, releases and more")
                        .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ExploreLinkCard(icon: "chart.line.uptrend.xyaxis", title: "Charts", subtitle: "Top music now") {
                            ChartsView()
                        }
                        ExploreLinkCard(icon: "sparkles", title: "New Releases", subtitle: "Fresh albums") {
                            NewReleasesView()
                        }
                        ExploreLinkCard(icon: "arrow.down.circle", title: "Downloads", subtitle: "Offline music") {
                            DownloadsView()
                        }
                        ExploreLinkCard(icon: "clock", title: "History", subtitle: "Recently played") {
                            HistoryView()
                        }
                    }
                    .padding(.horizontal)

                    MoodAndGenresView()

                    Spacer(minLength: 140)
                }
            }
            .vibesBackground()
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showSearch) {
                SearchView()
            }
        }
    }
}

private struct ExploreLinkCard<Destination: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let destination: () -> Destination

    init(icon: String, title: String, subtitle: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.destination = destination
    }

    var body: some View {
        NavigationLink(destination: destination()) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(VibesColors.accent)
                Text(title)
                    .font(.headline)
                    .foregroundColor(VibesColors.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(VibesColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(VibesColors.card)
            .cornerRadius(VibesRadius.card)
        }
        .buttonStyle(.plain)
    }
}
