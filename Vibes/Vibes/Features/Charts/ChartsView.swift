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
            VStack(alignment: .leading, spacing: 24) {
                if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if let error = errorMessage {
                        VStack(spacing: 14) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.largeTitle)
                                .foregroundColor(VibesColors.textTertiary)

                            Text(error)
                                .foregroundColor(VibesColors.textSecondary)

                            Button("Reintentar") {
                                Task {
                                    await loadCharts()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(VibesColors.accent)
                            .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else if let sections = chartsPage?.sections, !sections.isEmpty {
                        ForEach(sections.indices, id: \.self) { index in
                            ChartSectionView(section: sections[index])
                        }
                    } else {
                        VibesEmptyState(icon: "chart.line.uptrend.xyaxis", title: "No hay listas disponibles")
                    }

                Spacer(minLength: 140)
            }
            .padding(.top)
        }
        .vibesBackground()
        .navigationTitle("Éxitos")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadCharts()
        }
    }

    private func loadCharts() async {
        isLoading = true
        errorMessage = nil

        do {
            await MainActor.run { DebugLogger.shared.log("📊 charts vista: cargando...") }
            let page = try await ytMusic.getCharts()
            await MainActor.run {
                DebugLogger.shared.log("📊 charts vista: OK sections=\(page.sections.count)")
                chartsPage = page
            }
        } catch {
            dlog("❌ [Charts] Error loading charts: \(error)")
            await MainActor.run {
                DebugLogger.shared.log("❌ charts vista err=\(error)")
                errorMessage = "No se pudieron cargar las listas"
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
                .foregroundColor(VibesColors.textPrimary)
                .padding(.horizontal)

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
