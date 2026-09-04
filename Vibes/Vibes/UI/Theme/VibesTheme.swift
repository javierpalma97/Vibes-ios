import SwiftUI

// MARK: - Vibes Design System (mockup: dark + mint accent, rounded cards)

enum VibesColors {
    static let background = Color(red: 0.08, green: 0.085, blue: 0.11)
    static let card = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let elevated = Color(red: 0.18, green: 0.19, blue: 0.24)
    static let accent = Color(red: 0.24, green: 0.90, blue: 0.78)
    static let accentDim = Color(red: 0.24, green: 0.90, blue: 0.78).opacity(0.15)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let textTertiary = Color.white.opacity(0.4)
}

enum VibesRadius {
    static let card: CGFloat = 18
    static let row: CGFloat = 12
    static let pill: CGFloat = 22
}

struct VibesBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(VibesColors.background.ignoresSafeArea())
    }
}

extension View {
    func vibesBackground() -> some View {
        modifier(VibesBackground())
    }
}

// MARK: - Artwork

struct VibesArtwork: View {
    let url: String?
    let size: CGFloat
    var radius: CGFloat = 12
    var fallbackIcon: String = "music.note"

    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(VibesColors.elevated)
                .overlay(
                    Image(systemName: fallbackIcon)
                        .foregroundColor(VibesColors.textTertiary)
                )
        }
        .frame(width: size, height: size)
        .cornerRadius(radius)
    }
}

// MARK: - Search bar

struct VibesSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search songs, artists, playlists..."

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(VibesColors.textSecondary)
            TextField(placeholder, text: $text)
                .foregroundColor(VibesColors.textPrimary)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(VibesColors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(VibesColors.elevated)
        .cornerRadius(VibesRadius.pill)
    }
}

// MARK: - Section header

struct VibesSectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(VibesColors.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(VibesColors.textSecondary)
                }
            }
            Spacer()
            if let actionTitle = actionTitle {
                Button(action: { action?() }) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline)
                    .foregroundColor(VibesColors.accent)
                }
            }
        }
    }
}

// MARK: - Track row

struct VibesTrackRow: View {
    let song: Song
    var showArtwork: Bool = true
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 12) {
            if showArtwork {
                VibesArtwork(url: song.thumbnailUrl, size: 48, radius: 8)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(VibesColors.textPrimary)
                    .lineLimit(1)
                Text(song.artistsText ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundColor(VibesColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let trailing = trailing {
                trailing
            } else {
                DownloadStatusIndicator(songId: song.id)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Playlist / album / artist row

struct VibesMediaRow: View {
    let artworkUrl: String?
    let title: String
    let subtitle: String
    var fallbackIcon: String = "music.note.list"
    var onMenu: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VibesArtwork(url: artworkUrl, size: 56, radius: 10, fallbackIcon: fallbackIcon)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(VibesColors.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(VibesColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let onMenu = onMenu {
                Button(action: onMenu) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(VibesColors.textSecondary)
                        .padding(8)
                }
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(VibesColors.textTertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Cards

struct VibesPlaylistCard: View {
    let title: String
    let subtitle: String
    let artworkUrl: String?
    var width: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VibesArtwork(url: artworkUrl, size: width, radius: 14)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(VibesColors.textPrimary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(VibesColors.textSecondary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .frame(width: width)
    }
}

struct VibesQuickTile: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(VibesColors.textPrimary)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(VibesColors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(VibesColors.card)
            .cornerRadius(VibesRadius.card)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Library tabs

enum VibesLibraryTab: String, CaseIterable {
    case playlists = "Playlists"
    case albums = "Albums"
    case artists = "Artists"
    case downloads = "Downloads"
}

struct VibesLibraryTabs: View {
    @Binding var selection: VibesLibraryTab

    var body: some View {
        HStack(spacing: 20) {
            ForEach(VibesLibraryTab.allCases, id: \.self) { tab in
                Button(action: { selection = tab }) {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(selection == tab ? .semibold : .regular)
                            .foregroundColor(selection == tab ? VibesColors.textPrimary : VibesColors.textSecondary)
                        Rectangle()
                            .fill(selection == tab ? VibesColors.accent : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - Settings rows

struct VibesToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(VibesColors.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(VibesColors.textSecondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .tint(VibesColors.accent)
                .labelsHidden()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Empty state

struct VibesEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(VibesColors.textTertiary)
            Text(title)
                .font(.headline)
                .foregroundColor(VibesColors.textPrimary)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(VibesColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle = actionTitle {
                Button(actionTitle) { action?() }
                    .buttonStyle(.borderedProminent)
                    .tint(VibesColors.accent)
                    .foregroundColor(.black)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
