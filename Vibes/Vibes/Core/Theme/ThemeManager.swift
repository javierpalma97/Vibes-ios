import SwiftUI

@MainActor
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var primaryColor: Color = .blue
    @Published var secondaryColor: Color = .purple

    private init() {}

    /// Update theme colors based on artwork
    func updateTheme(from thumbnailUrl: String?) async {
        guard let thumbnailUrl = thumbnailUrl else {
            // Reset to default
            withAnimation(.easeInOut(duration: 0.5)) {
                primaryColor = .blue
                secondaryColor = .purple
            }
            return
        }

        let colors = await ThemeExtractor.extractColors(from: thumbnailUrl)

        withAnimation(.easeInOut(duration: 0.5)) {
            if colors.count >= 2 {
                primaryColor = colors[0]
                secondaryColor = colors[1]
            } else if colors.count == 1 {
                primaryColor = colors[0]
                secondaryColor = .purple
            }
        }
    }

    /// Get gradient for backgrounds
    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [primaryColor.opacity(0.3), secondaryColor.opacity(0.3), .black],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
