import Foundation

struct CUETrack {
    let trackNumber: Int
    let title: String
    let performer: String?
    let startTime: TimeInterval // in seconds
    let audioFileName: String
    let date: String?
    let genre: String?
}

struct CUESheet {
    let audioFileName: String
    let performer: String?
    let title: String?
    let date: String?
    let genre: String?
    let tracks: [CUETrack]

    /// True if tracks reference more than one distinct audio file
    var isMultiFile: Bool {
        Set(tracks.map { $0.audioFileName }).count > 1
    }
}

class CUEParser {

    /// Parse a .cue file at the given URL and return a CUESheet
    static func parse(url: URL) -> CUESheet? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            // Try other encodings
            guard let content = try? String(contentsOf: url, encoding: .isoLatin1) else {
                return nil
            }
            return parseContent(content, cueDirectory: url.deletingLastPathComponent())
        }
        return parseContent(content, cueDirectory: url.deletingLastPathComponent())
    }

    private static func parseContent(_ content: String, cueDirectory: URL) -> CUESheet? {
        let lines = content.components(separatedBy: .newlines)

        var globalFile: String?
        var globalPerformer: String?
        var globalTitle: String?
        var globalDate: String?
        var globalGenre: String?
        var currentTrackNumber: Int?
        var currentTitle: String?
        var currentPerformer: String?
        var currentFile: String?
        var currentDate: String?
        var currentGenre: String?
        var tracks: [CUETrack] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("FILE ") {
                currentFile = extractQuotedValue(from: trimmed, command: "FILE")
                if globalFile == nil {
                    globalFile = currentFile
                }
            } else if trimmed.hasPrefix("PERFORMER ") {
                let performer = extractQuotedValue(from: trimmed, command: "PERFORMER")
                if currentTrackNumber == nil {
                    globalPerformer = performer
                } else {
                    currentPerformer = performer
                }
            } else if trimmed.hasPrefix("TITLE ") {
                let title = extractQuotedValue(from: trimmed, command: "TITLE")
                if currentTrackNumber == nil {
                    globalTitle = title
                } else {
                    currentTitle = title
                }
            } else if trimmed.hasPrefix("REM ") {
                let rest = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if rest.uppercased().hasPrefix("DATE ") {
                    let value = extractRemValue(from: rest, command: "DATE")
                    if currentTrackNumber == nil { globalDate = value } else { currentDate = value }
                } else if rest.uppercased().hasPrefix("GENRE ") {
                    let value = extractRemValue(from: rest, command: "GENRE")
                    if currentTrackNumber == nil { globalGenre = value } else { currentGenre = value }
                }
            } else if trimmed.hasPrefix("TRACK ") {
                // Start new track
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let num = Int(parts[1]) {
                    currentTrackNumber = num
                    currentTitle = nil
                    currentPerformer = nil
                    currentDate = nil
                    currentGenre = nil
                }
            } else if trimmed.hasPrefix("INDEX 01 ") {
                // This is the main start index
                guard let trackNum = currentTrackNumber,
                      let file = currentFile ?? globalFile else { continue }

                let timeStr = String(trimmed.dropFirst("INDEX 01 ".count))
                let time = parseTimestamp(timeStr)

                tracks.append(CUETrack(
                    trackNumber: trackNum,
                    title: currentTitle ?? "Track \(trackNum)",
                    performer: currentPerformer ?? globalPerformer,
                    startTime: time,
                    audioFileName: file,
                    date: currentDate ?? globalDate,
                    genre: currentGenre ?? globalGenre
                ))
            }
        }

        guard let audioFile = globalFile ?? currentFile, !tracks.isEmpty else {
            return nil
        }

        return CUESheet(
            audioFileName: audioFile,
            performer: globalPerformer,
            title: globalTitle,
            date: globalDate,
            genre: globalGenre,
            tracks: tracks
        )
    }

    /// Parse CUE timestamp format MM:SS:FF (frames, 75 fps)
    private static func parseTimestamp(_ str: String) -> TimeInterval {
        let parts = str.split(separator: ":")
        guard parts.count == 3,
              let minutes = Int(parts[0]),
              let seconds = Int(parts[1]),
              let frames = Int(parts[2]) else {
            return 0
        }
        return Double(minutes) * 60.0 + Double(seconds) + Double(frames) / 75.0
    }

    /// Extract a quoted value from a CUE command line
    /// e.g., `FILE "album.flac" WAVE` → `album.flac`
    private static func extractQuotedValue(from line: String, command: String) -> String? {
        let afterCommand = String(line.dropFirst(command.count)).trimmingCharacters(in: .whitespaces)

        if afterCommand.hasPrefix("\"") {
            // Find closing quote
            let content = String(afterCommand.dropFirst())
            if let endQuote = content.firstIndex(of: "\"") {
                return String(content[content.startIndex..<endQuote])
            }
            return content
        }

        // No quotes — take first word
        return afterCommand.split(separator: " ").first.map(String.init)
    }

    /// Extract value from a REM line. e.g. `DATE 1974` → `1974`, `GENRE "Prog Rock"` → `Prog Rock`
    private static func extractRemValue(from line: String, command: String) -> String? {
        let afterCommand = String(line.dropFirst(command.count)).trimmingCharacters(in: .whitespaces)
        if afterCommand.hasPrefix("\"") {
            let content = String(afterCommand.dropFirst())
            if let endQuote = content.firstIndex(of: "\"") {
                return String(content[content.startIndex..<endQuote])
            }
            return content
        }
        return afterCommand.isEmpty ? nil : afterCommand
    }
}
