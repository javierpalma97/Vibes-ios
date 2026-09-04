import SwiftUI

struct BrowseView: View {
    let browseId: String
    let params: String?
    let title: String

    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager

    @State private var sections: [BrowseSection] = []
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
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(VibesColors.textTertiary)

                    Text(error)
                        .foregroundColor(VibesColors.textSecondary)

                    Button("Retry") {
                        Task {
                            await loadContent()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VibesColors.accent)
                    .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else if sections.isEmpty {
                VibesEmptyState(icon: "music.note", title: "No content available")
                    .padding(.top, 60)
            } else {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(sections.indices, id: \.self) { index in
                        BrowseSectionView(section: sections[index])
                    }
                }
                .padding(.top)
            }

            Spacer(minLength: 140)
        }
        .vibesBackground()
        .navigationTitle(title)
        .task {
            await loadContent()
        }
    }

    private func loadContent() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await ytMusic.browsePage(browseId: browseId, params: params)
            await MainActor.run {
                sections = result.sections
            }
        } catch {
            dlog("❌ [Browse] Error loading content: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load content"
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }
}

// MARK: - Browse Section View

struct BrowseSectionView: View {
    let section: BrowseSection
    @EnvironmentObject var queueManager: QueueManager
    @EnvironmentObject var libraryManager: LibraryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = section.title {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(VibesColors.textPrimary)
                    .padding(.horizontal)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(section.items.indices, id: \.self) { index in
                        HomeItemView(item: section.items[index])
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Browse Models

struct BrowseResult {
    let title: String?
    let sections: [BrowseSection]
}

struct BrowseSection {
    let title: String?
    let items: [HomeItem]
}
