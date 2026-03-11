import SwiftUI

struct LyricsLine: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

struct SyncedLyricsView: View {
    let lyrics: String
    let currentTime: TimeInterval
    let isPlaying: Bool

    @State private var parsedLines: [LyricsLine] = []
    @State private var isSynced: Bool = false

    var body: some View {
        Group {
            if isSynced {
                syncedView
            } else {
                plainView
            }
        }
        .onAppear { parseLines() }
        .onChange(of: lyrics) { _, _ in parseLines() }
    }

    // MARK: - Synced Lyrics View

    private var syncedView: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(parsedLines.enumerated()), id: \.element.id) { index, line in
                    let isActive = isActiveLine(index: index)
                    let isPast = isPastLine(index: index)

                    Text(line.text)
                        .font(.system(size: isActive ? 16 : 14, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? .primary : (isPast ? .secondary : .secondary.opacity(0.6)))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, isActive ? 4 : 1)
                        .id(line.id)
                        .animation(.easeInOut(duration: 0.3), value: isActive)
                }
            }
            .padding(.vertical, 8)
            .onChange(of: activeLineIndex) { _, newIndex in
                if let newIndex, newIndex < parsedLines.count {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(parsedLines[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Plain Lyrics View

    private var plainView: some View {
        Text(lyrics)
            .font(.body)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    // MARK: - Line State

    private var activeLineIndex: Int? {
        guard !parsedLines.isEmpty else { return nil }

        var lastIndex: Int? = nil
        for (index, line) in parsedLines.enumerated() {
            if currentTime >= line.time {
                lastIndex = index
            } else {
                break
            }
        }
        return lastIndex
    }

    private func isActiveLine(index: Int) -> Bool {
        return index == activeLineIndex
    }

    private func isPastLine(index: Int) -> Bool {
        guard let active = activeLineIndex else { return false }
        return index < active
    }

    // MARK: - LRC Parsing

    private func parseLines() {
        let lines = lyrics.components(separatedBy: .newlines)
        var result: [LyricsLine] = []

        for line in lines {
            guard let parsed = parseLRCLine(line) else { continue }
            if !parsed.text.isEmpty {
                result.append(LyricsLine(time: parsed.time, text: parsed.text))
            }
        }

        if result.count >= 3 {
            // Sort by time and use synced mode
            result.sort { $0.time < $1.time }
            parsedLines = result
            isSynced = true
        } else {
            // Not enough synced lines, treat as plain text
            isSynced = false
        }
    }

    private func parseLRCLine(_ line: String) -> (time: TimeInterval, text: String)? {
        // Expected format: [MM:SS.xx] text  or  [MM:SS.xxx] text
        guard line.hasPrefix("[") else { return nil }
        guard let closeBracket = line.firstIndex(of: "]") else { return nil }

        let timeStr = String(line[line.index(after: line.startIndex)..<closeBracket])
        let text = String(line[line.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)

        let parts = timeStr.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]) else { return nil }

        let secParts = parts[1].split(separator: ".")
        guard secParts.count == 2,
              let seconds = Double(secParts[0]),
              let frac = Double(secParts[1]) else { return nil }

        let divisor = secParts[1].count == 3 ? 1000.0 : 100.0
        let time = minutes * 60 + seconds + frac / divisor

        return (time, text)
    }
}
