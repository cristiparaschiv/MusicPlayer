import AppKit
import SwiftUI

/// Manages the mini player floating window
class MiniPlayerWindowManager {
    static let shared = MiniPlayerWindowManager()

    private var window: NSPanel?

    private init() {}

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func toggle() {
        if let window = window, window.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 76),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        panel.contentView = NSHostingView(rootView: MiniPlayerView())

        // Position at top-right of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 300 - 20
            let y = screenFrame.maxY - 76 - 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        self.window = panel
    }

    func close() {
        window?.close()
    }
}
