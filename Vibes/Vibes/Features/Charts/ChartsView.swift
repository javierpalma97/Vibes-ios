import SwiftUI

struct ChartsView: View {
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager

    @State private var chartsPage: ChartsPage?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let ytMusic = YouTubeMusic.shared

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    Text(error)
                        .foregroundColor(.secondary)

                    Button("Retry") {
                        Task {
                            await loadCharts()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else if let sections = chartsPage?.sections {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(sections.indices, id: \.self) { index in
                        ChartSectionView(section: sections[index])
                    }
                }
                .padding(.top)
            }

            Spacer(minLength: 120)
        }
        .navigationTitle("Charts")
        .task {
            await loadCharts()
        }
    }

    private func loadCharts() async {
        isLoading = true
        errorMessage = nil

        do {
            let page = try await ytMusic.getCharts()
            await MainActor.run {
                chartsPage = page
            }
        } catch {
            print("❌ [Charts] Error loading charts: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load charts"
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }
}

// MARK: - Chart Section View

struct ChartSectionView: View {
    let section: ChartSection
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(section.items.indices, id: \.self) { index in
                        HomeItemView(item: section.items[index])
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
