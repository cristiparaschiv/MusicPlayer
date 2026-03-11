import Foundation
import AppKit

/// Encodes/decodes track IDs for drag-and-drop as a plain String (Transferable).
enum TrackDragHelper {
    static let prefix = "orangemusicplayer-trackids:"

    /// Custom pasteboard type for track drags
    static let pasteboardType = NSPasteboard.PasteboardType("com.orangemusicplayer.trackids")

    /// Encode track IDs into a draggable string
    static func encode(_ trackIDs: [Int64]) -> String {
        prefix + trackIDs.map { String($0) }.joined(separator: ",")
    }

    /// Decode track IDs from a dropped string. Returns nil if not our format.
    static func decode(_ string: String) -> [Int64]? {
        guard string.hasPrefix(prefix) else { return nil }
        let idsString = string.dropFirst(prefix.count)
        let ids = idsString.split(separator: ",").compactMap { Int64($0) }
        return ids.isEmpty ? nil : ids
    }
}
