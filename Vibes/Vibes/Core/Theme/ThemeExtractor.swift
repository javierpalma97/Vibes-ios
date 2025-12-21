import UIKit
import SwiftUI

/// Extracts dominant colors from album artwork for dynamic theming
class ThemeExtractor {

    /// Extract the top 2 dominant colors from an image
    static func extractColors(from image: UIImage) -> [Color] {
        // Resize image to 100x100 for faster processing
        guard let resizedImage = resizeImage(image, to: CGSize(width: 100, height: 100)),
              let pixelData = getPixelData(from: resizedImage) else {
            return [.blue, .purple]  // Default fallback
        }

        // Count color frequencies
        var colorFrequency: [UIColor: Int] = [:]

        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let r = CGFloat(pixelData[i]) / 255.0
            let g = CGFloat(pixelData[i + 1]) / 255.0
            let b = CGFloat(pixelData[i + 2]) / 255.0
            let a = CGFloat(pixelData[i + 3]) / 255.0

            // Skip very dark or very light colors (not good for backgrounds)
            let brightness = (r + g + b) / 3.0
            guard brightness > 0.2 && brightness < 0.8 && a > 0.5 else {
                continue
            }

            // Quantize colors to reduce similar shades
            let quantizedR = round(r * 4) / 4
            let quantizedG = round(g * 4) / 4
            let quantizedB = round(b * 4) / 4

            let color = UIColor(red: quantizedR, green: quantizedG, blue: quantizedB, alpha: 1.0)
            colorFrequency[color, default: 0] += 1
        }

        // Sort by frequency and take top 2
        let sortedColors = colorFrequency.sorted { $0.value > $1.value }
            .prefix(2)
            .map { Color($0.key) }

        if sortedColors.count >= 2 {
            return Array(sortedColors)
        } else if sortedColors.count == 1 {
            // Generate complementary color
            return [sortedColors[0], generateComplementary(sortedColors[0])]
        } else {
            return [.blue, .purple]
        }
    }

    /// Resize image for faster processing
    private static func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Get pixel data from image
    private static func getPixelData(from image: UIImage) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return pixelData
    }

    /// Generate complementary color
    private static func generateComplementary(_ color: Color) -> Color {
        // Convert to HSB and rotate hue by 180 degrees
        let uiColor = UIColor(color)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Rotate hue by 180 degrees for complementary color
        let complementaryHue = fmod(hue + 0.5, 1.0)

        return Color(hue: complementaryHue, saturation: saturation, brightness: brightness, opacity: alpha)
    }

    /// Extract colors from URL asynchronously
    static func extractColors(from urlString: String) async -> [Color] {
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else {
            return [.blue, .purple]
        }

        return extractColors(from: image)
    }
}
