import Foundation
import CryptoKit

struct ScriptMetadata: Identifiable {
    let id: UUID
    let fileURL: URL
    let name: String
    let description: String
    let author: String
    let event: String?       // nil = on-demand only
    let shortcut: String?    // e.g. "cmd+shift+1"
    var isEnabled: Bool
    var status: ScriptStatus

    enum ScriptStatus: Equatable {
        case idle
        case running
        case error(String)
    }
}

extension ScriptMetadata {
    /// Parse metadata from the leading comment block of a .js file.
    /// Expects lines like: // @name My Script
    static func parse(from fileURL: URL) -> ScriptMetadata? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        var name: String?
        var description = ""
        var author = ""
        var event: String?
        var shortcut: String?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip blank lines, stop at first non-comment line
            if trimmed.isEmpty { continue }
            guard trimmed.hasPrefix("//") else { break }

            let commentBody = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)

            if commentBody.hasPrefix("@name") {
                name = String(commentBody.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if commentBody.hasPrefix("@description") {
                description = String(commentBody.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            } else if commentBody.hasPrefix("@author") {
                author = String(commentBody.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if commentBody.hasPrefix("@event") {
                event = String(commentBody.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if commentBody.hasPrefix("@shortcut") {
                shortcut = String(commentBody.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            }
        }

        let scriptName = (name?.isEmpty == false) ? name! : fileURL.deletingPathExtension().lastPathComponent

        // Stable UUID derived from the file path so IDs survive reloads
        let pathData = Data(fileURL.path.utf8)
        let hash = SHA256.hash(data: pathData)
        let bytes = Array(hash.prefix(16))
        let stableID = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                                    bytes[4], bytes[5], bytes[6], bytes[7],
                                    bytes[8], bytes[9], bytes[10], bytes[11],
                                    bytes[12], bytes[13], bytes[14], bytes[15]))

        return ScriptMetadata(
            id: stableID,
            fileURL: fileURL,
            name: scriptName,
            description: description,
            author: author,
            event: event,
            shortcut: shortcut,
            isEnabled: true,
            status: .idle
        )
    }
}
