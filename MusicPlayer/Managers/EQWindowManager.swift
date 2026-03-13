import AppKit
import SwiftUI

class AudioEffectsWindowManager {
    static let shared = AudioEffectsWindowManager()

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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.title = "Audio Effects"
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        panel.contentView = NSHostingView(rootView: AudioEffectsView())

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 260
            let y = screenFrame.midY - 190
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        self.window = panel
    }

    func close() {
        window?.close()
    }
}
