import Foundation
import AppKit

// MARK: - String Extensions
extension String {
    var sortKey: String {
        let prefixes = ["The ", "A ", "An "]
        var result = self
        for prefix in prefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                break
            }
        }
        return result.lowercased()
    }

    func sanitizedForSQL() -> String {
        return self.replacingOccurrences(of: "'", with: "''")
    }
}

// MARK: - TimeInterval Extensions
extension TimeInterval {
    var formattedDuration: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - FileManager Extensions
extension FileManager {
    func applicationSupportDirectory() -> URL {
        let urls = self.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportURL = urls[0].appendingPathComponent("OrangeMusicPlayer")

        if !fileExists(atPath: appSupportURL.path) {
            try? createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }

        return appSupportURL
    }

    func cacheDirectory(for subdirectory: String) -> URL {
        let cacheURL = applicationSupportDirectory().appendingPathComponent(subdirectory)

        if !fileExists(atPath: cacheURL.path) {
            try? createDirectory(at: cacheURL, withIntermediateDirectories: true)
        }

        return cacheURL
    }
}

extension NSImage {
    func resized(to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        let context = NSGraphicsContext.current
        context?.imageInterpolation = .high
        self.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    static func placeholder(for type: String, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.systemGray.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size.width / 8),
            .foregroundColor: NSColor.white
        ]

        let text = type == "artist" ? "♪" : "♫"
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )

        text.draw(in: textRect, withAttributes: attributes)
        image.unlockFocus()

        return image
    }
}
