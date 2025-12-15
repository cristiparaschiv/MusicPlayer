import AppKit
import CoreImage
import SwiftUI

/// Utility class to extract dominant colors from images
class ColorExtractor {

    /// Extract dominant color from an NSImage
    /// - Parameter image: The image to analyze
    /// - Returns: A Color representing the dominant color, or nil if extraction fails
    static func extractDominantColor(from image: NSImage) -> Color? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // Resize image to speed up processing
        let size = CGSize(width: 100, height: 100)
        guard let resizedImage = resizeImage(cgImage, to: size) else {
            return nil
        }

        // Extract color
        if let dominantColor = getDominantColor(from: resizedImage) {
            return Color(nsColor: dominantColor)
        }

        return nil
    }

    /// Extract a color palette from an NSImage
    /// - Parameters:
    ///   - image: The image to analyze
    ///   - maxColors: Maximum number of colors to extract
    /// - Returns: Array of dominant colors
    static func extractColorPalette(from image: NSImage, maxColors: Int = 5) -> [Color] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        // Resize image to speed up processing
        let size = CGSize(width: 100, height: 100)
        guard let resizedImage = resizeImage(cgImage, to: size) else {
            return []
        }

        // Simple color extraction based on sampling
        var colors: [NSColor] = []

        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }

        context.draw(resizedImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))

        // Sample pixels and find dominant colors
        var colorCounts: [NSColor: Int] = [:]

        for y in stride(from: 0, to: height, by: 10) {
            for x in stride(from: 0, to: width, by: 10) {
                let pixelIndex = (y * width + x) * bytesPerPixel
                let r = CGFloat(pixelData[pixelIndex]) / 255.0
                let g = CGFloat(pixelData[pixelIndex + 1]) / 255.0
                let b = CGFloat(pixelData[pixelIndex + 2]) / 255.0

                // Skip very dark or very light colors
                let brightness = (r + g + b) / 3.0
                if brightness < 0.15 || brightness > 0.9 {
                    continue
                }

                let color = NSColor(red: r, green: g, blue: b, alpha: 1.0)
                colorCounts[color, default: 0] += 1
            }
        }

        // Sort by frequency and take top colors
        colors = colorCounts.sorted { $0.value > $1.value }
            .prefix(maxColors)
            .map { $0.key }

        return colors.map { Color(nsColor: $0) }
    }

    // MARK: - Private Helpers

    private static func resizeImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))

        return context.makeImage()
    }

    private static func getDominantColor(from image: CGImage) -> NSColor? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Calculate average color
        var totalRed: CGFloat = 0
        var totalGreen: CGFloat = 0
        var totalBlue: CGFloat = 0
        var count = 0

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * bytesPerPixel
                let r = CGFloat(pixelData[pixelIndex]) / 255.0
                let g = CGFloat(pixelData[pixelIndex + 1]) / 255.0
                let b = CGFloat(pixelData[pixelIndex + 2]) / 255.0

                // Skip very dark or very light pixels
                let brightness = (r + g + b) / 3.0
                if brightness < 0.15 || brightness > 0.9 {
                    continue
                }

                totalRed += r
                totalGreen += g
                totalBlue += b
                count += 1
            }
        }

        guard count > 0 else { return nil }

        let avgRed = totalRed / CGFloat(count)
        let avgGreen = totalGreen / CGFloat(count)
        let avgBlue = totalBlue / CGFloat(count)

        return NSColor(red: avgRed, green: avgGreen, blue: avgBlue, alpha: 1.0)
    }
}
