import SwiftUI

struct SectionIndexView: View {
    let availableLetters: Set<String>
    let onSelect: (String) -> Void

    private static let allLetters = (65...90).map { String(UnicodeScalar($0)) } + ["#"]

    @State private var isDragging = false
    @State private var hoveredLetter: String?

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Self.allLetters, id: \.self) { letter in
                let isAvailable = availableLetters.contains(letter)
                Text(letter)
                    .font(.system(size: 10, weight: hoveredLetter == letter ? .bold : .medium, design: .rounded))
                    .foregroundStyle(
                        hoveredLetter == letter ? Color.accentColor :
                        isAvailable ? .primary : .secondary.opacity(0.3)
                    )
                    .frame(width: 16, height: 13)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .opacity(isDragging ? 1 : 0)
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    let letterHeight: CGFloat = 13
                    let padding: CGFloat = 4
                    let index = Int((value.location.y - padding) / letterHeight)
                    let clamped = max(0, min(index, Self.allLetters.count - 1))
                    let letter = Self.allLetters[clamped]
                    if hoveredLetter != letter && availableLetters.contains(letter) {
                        hoveredLetter = letter
                        onSelect(letter)
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    hoveredLetter = nil
                }
        )
        .padding(.trailing, 4)
    }
}
