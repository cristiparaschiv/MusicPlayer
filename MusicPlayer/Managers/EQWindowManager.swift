import AppKit
import SwiftUI

class EQWindowManager {
    static let shared = EQWindowManager()

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
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.title = "Equalizer"
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        panel.contentView = NSHostingView(rootView: EQView())

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 240
            let y = screenFrame.midY - 150
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        self.window = panel
    }

    func close() {
        window?.close()
    }
}
