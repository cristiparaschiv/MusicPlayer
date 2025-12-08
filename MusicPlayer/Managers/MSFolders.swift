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

            // Handle multiple selected folders
            for url in openPanel.urls {
                // Create security-scoped bookmark for persistent access
                if SecurityBookmarkManager.shared.createBookmark(for: url) {
                    print("✅ Security bookmark created for: \(url.path)")
                    MediaScannerManager.shared.addLibraryPath(url.path)
                } else {
                    print("⚠️ Failed to create security bookmark for: \(url.path)")
                    // Still add the path, but access may fail on restart
                    MediaScannerManager.shared.addLibraryPath(url.path)
                }
            }
        }
    }
}
