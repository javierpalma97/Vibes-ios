import SwiftUI
import SwiftData

enum Tab {
    case home
    case search
    case library
}

struct ContentView: View {
    @EnvironmentObject var playerManager: PlayerManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var lyricsManager: LyricsManager
    @EnvironmentObject var themeManager: ThemeManager

    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: Tab = .home
    @State private var showPlayer: Bool = false
    @State private var showQueue: Bool = false
    @State private var showSettings: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            TabView(selection: $selectedTab) {
                HomeView()
                    .tag(Tab.home)
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }

                SearchView()
                    .tag(Tab.search)
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }

                LibraryView()
                    .tag(Tab.library)
                    .tabItem {
                        Label("Library", systemImage: "music.note.list")
                    }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }

            // Mini player
            if playerManager.currentSong != nil {
                MiniPlayerView(
                    onTap: { showPlayer = true },
                    onQueueTap: { showQueue = true }
                )
                .padding(.bottom, 49) // Tab bar height
            }
        }
        .sheet(isPresented: $showPlayer) {
            PlayerView()
                .environmentObject(lyricsManager)
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
}

struct MiniPlayerView: View {
    @EnvironmentObject var playerManager: PlayerManager
    @EnvironmentObject var queueManager: QueueManager

    let onTap: () -> Void
    let onQueueTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            if playerManager.duration > 0 {
                ProgressView(value: playerManager.currentTime, total: playerManager.duration)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                    .frame(height: 2)
            }

            // Player controls
            HStack(spacing: 12) {
                // Thumbnail
                AsyncImage(url: URL(string: playerManager.currentSong?.thumbnailUrl ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 48, height: 48)
                .cornerRadius(8)

                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(playerManager.currentSong?.title ?? "")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(playerManager.currentSong?.artistsText ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Play/Pause button
                Button(action: {
                    playerManager.togglePlayPause()
                }) {
                    Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(.primary)
                }

                // Next button
                Button(action: {
                    playerManager.playNext()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .foregroundColor(.primary)
                }

                // Queue button
                Button(action: onQueueTap) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))
            .shadow(color: Color.black.opacity(0.1), radius: 10, y: -5)
        }
        .onTapGesture(perform: onTap)
    }
}
