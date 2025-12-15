import Foundation
import AppKit

extension MediaScannerManager {
    func addFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.prompt = "Add Music Folder"
        openPanel.message = "Select folders containing your music collection"

        openPanel.begin { response in
            guard response == .OK else { return }

            let urls = openPanel.urls
            guard !urls.isEmpty else { return }

            // Handle multiple selected folders - add all paths first without scanning
            for url in urls {
                // Create security-scoped bookmark for persistent access
                if SecurityBookmarkManager.shared.createBookmark(for: url) {
                    MediaScannerManager.shared.addLibraryPath(url.path, triggerScan: false)
                } else {
                    // Still add the path, but access may fail on restart
                    MediaScannerManager.shared.addLibraryPath(url.path, triggerScan: false)
                }
            }

            // Trigger a single scan after all paths have been added
            MediaScannerManager.shared.scanForChanges()
        }
    }
}
