import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var lyricsManager: LyricsManager
    @EnvironmentObject var playerManager: PlayerManager

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    if let lyrics = lyricsManager.currentLyrics {
                        if lyrics.synced {
                            // Synced lyrics with timestamps
                            ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                                LyricsLineView(
                                    line: line,
                                    isCurrentLine: index == lyricsManager.currentLineIndex,
                                    distance: abs(index - lyricsManager.currentLineIndex)
                                ) {
                                    // Tap to seek
                                    if let timestamp = line.timestamp {
                                        playerManager.seek(to: timestamp)
                                    }
                                }
                                .id(index)
                            }
                        } else {
                            // Unsynced lyrics (plain text)
                            ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                                LyricsLineView(
                                    line: line,
                                    isCurrentLine: false,
                                    distance: 0
                                )
                                .id(index)
                            }
                        }
                    } else {
                        // No lyrics available
                        VStack(spacing: 16) {
                            Image(systemName: "text.quote")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary.opacity(0.5))

                            Text("Sin letra disponible")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 40)
            }
            .onChange(of: lyricsManager.currentLineIndex) { _, newIndex in
                // Auto-scroll to current line
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .background(Color.black.opacity(0.3))
    }
}

struct LyricsLineView: View {
    let line: LyricsLine
    let isCurrentLine: Bool
    let distance: Int  // Distance from current line
    var onTap: (() -> Void)? = nil

    @State private var romanized: String?

    var body: some View {
        Button(action: {
            onTap?()
        }) {
            VStack(spacing: 4) {
                // Original text
                Text(line.text)
                    .font(isCurrentLine ? .title2 : .body)
                    .fontWeight(isCurrentLine ? .bold : .regular)
                    .foregroundColor(.white)
                    .opacity(lineOpacity)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.2), value: isCurrentLine)

                // Romanization (if available)
                if let romanized = romanized, !romanized.isEmpty, romanized != line.text {
                    Text(romanized)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .opacity(lineOpacity * 0.8)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            // Romanize on appear
            romanized = LyricsRomanizer.romanize(line.text)
        }
    }

    private var lineOpacity: Double {
        if isCurrentLine {
            return 1.0
        } else if distance == 1 {
            return 0.7
        } else if distance == 2 {
            return 0.5
        } else {
            return 0.3
        }
    }
}
