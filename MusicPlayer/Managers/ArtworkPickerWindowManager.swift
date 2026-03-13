import AppKit
import SwiftUI

class ArtworkPickerWindowManager {
    static let shared = ArtworkPickerWindowManager()

    private var window: NSPanel?

    private init() {}

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func show(for album: Album) {
        // Close existing window if open
        close()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 580),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "Choose Artwork — \(album.title)"
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: 500, height: 400)

        let pickerView = ArtworkPickerView(album: album) { [weak self] in
            self?.close()
        }
        panel.contentView = NSHostingView(rootView: pickerView)

        // Position relative to main window
        if let mainWindow = NSApp.mainWindow {
            let mainFrame = mainWindow.frame
            let x = mainFrame.midX - 340
            let y = mainFrame.midY - 290
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            panel.parent = mainWindow
        } else if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: screenFrame.midX - 340,
                y: screenFrame.midY - 290
            ))
        }

        panel.makeKeyAndOrderFront(nil)
        self.window = panel
    }

    func close() {
        window?.close()
        window = nil
    }
}
