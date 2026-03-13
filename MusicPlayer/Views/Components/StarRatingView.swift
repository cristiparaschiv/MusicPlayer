import SwiftUI

struct StarRatingView: View {
    let rating: Int?
    let size: CGFloat
    var onRate: ((Int?) -> Void)?

    init(rating: Int?, size: CGFloat = 14, onRate: ((Int?) -> Void)? = nil) {
        self.rating = rating
        self.size = size
        self.onRate = onRate
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundColor(star <= (rating ?? 0) ? .orange : .secondary.opacity(0.4))
                    .onTapGesture {
                        if let onRate {
                            // Tap same star to clear rating
                            if rating == star {
                                onRate(nil)
                            } else {
                                onRate(star)
                            }
                        }
                    }
            }
        }
        .accessibilityLabel("Rating: \(rating.map { "\($0) of 5 stars" } ?? "unrated")")
    }
}

// NSView version for use in NSTableView
class StarRatingNSView: NSView {
    var rating: Int? = nil {
        didSet { needsDisplay = true }
    }
    var onRate: ((Int?) -> Void)?

    private let starCount = 5
    private let starSize: CGFloat = 12
    private let spacing: CGFloat = 2

    override var intrinsicContentSize: NSSize {
        let width = CGFloat(starCount) * starSize + CGFloat(starCount - 1) * spacing
        return NSSize(width: width, height: starSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let currentRating = rating ?? 0
        for i in 0..<starCount {
            let x = CGFloat(i) * (starSize + spacing)
            let rect = NSRect(x: x, y: (bounds.height - starSize) / 2, width: starSize, height: starSize)
            let symbolName = (i + 1) <= currentRating ? "star.fill" : "star"
            let config = NSImage.SymbolConfiguration(pointSize: starSize, weight: .regular)
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let tint: NSColor = (i + 1) <= currentRating ? .orange : .secondaryLabelColor.withAlphaComponent(0.4)
                let tinted = image.tinted(with: tint)
                tinted.draw(in: rect)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedStar = Int(point.x / (starSize + spacing)) + 1
        guard clickedStar >= 1, clickedStar <= starCount else { return }
        if rating == clickedStar {
            onRate?(nil)
        } else {
            onRate?(clickedStar)
        }
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
