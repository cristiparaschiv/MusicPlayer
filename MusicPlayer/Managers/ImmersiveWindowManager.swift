import AppKit
import SwiftUI

class ImmersiveWindowManager {
    static let shared = ImmersiveWindowManager()

    private var window: NSWindow?

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

        guard let screen = NSScreen.main else { return }

        // Use a borderless window that covers the entire screen including menu bar
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.setFrame(screen.frame, display: true)

        // Hide menu bar and dock
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]

        let hostingView = NSHostingView(rootView: ImmersiveNowPlayingView {
            self.close()
        })
        window.contentView = hostingView

        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func close() {
        guard let window = window else { return }

        // Restore menu bar and dock
        NSApp.presentationOptions = []

        window.orderOut(nil)
        window.close()
        self.window = nil
    }
}
