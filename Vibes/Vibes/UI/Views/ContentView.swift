import SwiftUI
import SwiftData

enum VibesTab: String, CaseIterable {
    case home = "Home"
    case explore = "Explore"
    case play = "Play"
    case library = "Library"
    case profile = "Profile"

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "safari"
        case .play: return "play.fill"
        case .library: return "square.stack.fill"
        case .profile: return "person.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var playerManager: PlayerManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var lyricsManager: LyricsManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab: VibesTab = .home
    @State private var showPlayer: Bool = false
    @State private var showQueue: Bool = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                ipadLayout
            } else {
                iphoneLayout
            }
        }
        .preferredColorScheme(.dark)
        .accentColor(VibesColors.accent)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
                .environmentObject(playerManager)
                .environmentObject(authManager)
                .environmentObject(libraryManager)
                .environmentObject(lyricsManager)
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
        .onAppear {
            libraryManager.setModelContext(modelContext)
            lyricsManager.setModelContext(modelContext)
        }
        .onChange(of: playerManager.shouldShowFullPlayer) { _, shouldShow in
            if shouldShow {
                showPlayer = true
                playerManager.shouldShowFullPlayer = false
            }
        }
    }

    // MARK: - iPhone (tab bar)

    private var iphoneLayout: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .vibesBackground()

            VStack(spacing: 0) {
                if playerManager.currentSong != nil {
                    VibesMiniPlayer(
                        onTap: { showPlayer = true },
                        onQueueTap: { showQueue = true }
                    )
                    .padding(.horizontal, 12)
                }
                VibesTabBar(selection: $selectedTab)
            }
        }
    }

    // MARK: - iPad (sidebar)

    private var ipadLayout: some View {
        NavigationSplitView {
            List(VibesTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .foregroundColor(selectedTab == tab ? VibesColors.accent : VibesColors.textPrimary)
            }
            .navigationTitle("Vibes")
            .vibesBackground()
        } detail: {
            ZStack(alignment: .bottom) {
                tabContent
                    .vibesBackground()
                if playerManager.currentSong != nil {
                    VibesMiniPlayer(
                        onTap: { showPlayer = true },
                        onQueueTap: { showQueue = true }
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            HomeView()
        case .explore:
            ExploreView()
        case .play:
            NavigationStack {
                ChartsView()
            }
        case .library:
            LibraryView()
        case .profile:
            NavigationStack {
                AccountView()
            }
        }
    }
}

// MARK: - Custom tab bar

struct VibesTabBar: View {
    @Binding var selection: VibesTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(VibesTab.allCases, id: \.self) { tab in
                Button(action: { selection = tab }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 22))
                        Text(tab.rawValue)
                            .font(.caption2)
                    }
                    .foregroundColor(selection == tab ? VibesColors.accent : VibesColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 18)
        .background(VibesColors.card.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - Floating mini player

struct VibesMiniPlayer: View {
    @EnvironmentObject var playerManager: PlayerManager
    @EnvironmentObject var queueManager: QueueManager

    let onTap: () -> Void
    let onQueueTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VibesArtwork(url: playerManager.currentSong?.thumbnailUrl, size: 44, radius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playerManager.currentSong?.title ?? "")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(VibesColors.textPrimary)
                        .lineLimit(1)
                    Text(playerManager.currentSong?.artistsText ?? "")
                        .font(.caption)
                        .foregroundColor(VibesColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: { playerManager.togglePlayPause() }) {
                    Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(VibesColors.textPrimary)
                }
                Button(action: { playerManager.playNext() }) {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .foregroundColor(VibesColors.textPrimary)
                }
                Button(action: onQueueTap) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundColor(VibesColors.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            if playerManager.duration > 0 {
                ProgressView(value: playerManager.currentTime, total: playerManager.duration)
                    .progressViewStyle(LinearProgressViewStyle(tint: VibesColors.accent))
                    .frame(height: 2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(VibesColors.elevated)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.4), radius: 12, y: -4)
        .onTapGesture(perform: onTap)
    }
}
