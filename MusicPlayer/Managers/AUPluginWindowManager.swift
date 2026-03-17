import AppKit
import SwiftUI
import AVFoundation
import CoreAudioKit

// MARK: - AUPluginWindowManager

/// Manages floating NSPanel windows for AU plugin UIs.
final class AUPluginWindowManager {
    static let shared = AUPluginWindowManager()

    /// Open panels keyed by EffectSlot id.
    private(set) var openPanels: [UUID: NSPanel] = [:]

    private init() {}

    // MARK: - Open

    /// Opens (or brings forward) the UI panel for the given AUPluginSlot.
    func openPluginUI(for slot: AUPluginSlot, engine: AVAudioEngine?) {
        // Bring existing panel to front if already open.
        if let existing = openPanels[slot.id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        // Try to find the AU from the provided engine, or from any active node
        let auAudioUnit: AUAudioUnit? = {
            if let engine = engine {
                return slot.audioUnit(for: engine)
            }
            // Fallback: try to get the AU from any active engine
            return slot.anyAudioUnit
        }()

        guard let auAudioUnit = auAudioUnit else {
            // AU hasn't been instantiated yet — open a placeholder panel.
            openFallbackPanel(for: slot, auAudioUnit: nil)
            return
        }

        // Request the plugin's custom view controller (CoreAudioKit extension on AUAudioUnit).
        auAudioUnit.requestViewController { [weak self] (viewController: NSViewController?) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let vc = viewController {
                    self.openCustomVCPanel(for: slot, viewController: vc, title: slot.displayName)
                } else {
                    self.openFallbackPanel(for: slot, auAudioUnit: auAudioUnit)
                }
            }
        }
    }

    // MARK: - Close

    func closePluginUI(for slot: AUPluginSlot) {
        openPanels[slot.id]?.close()
        openPanels.removeValue(forKey: slot.id)
    }

    func closeAll() {
        openPanels.values.forEach { $0.close() }
        openPanels.removeAll()
    }

    // MARK: - Panel builders

    private func openCustomVCPanel(for slot: AUPluginSlot, viewController: NSViewController, title: String) {
        let panel = makePanel(title: title)

        // Size the panel to the plugin's preferred content size, with sensible fallback.
        let preferredSize = viewController.preferredContentSize
        let width  = preferredSize.width  > 0 ? preferredSize.width  : 400
        let height = preferredSize.height > 0 ? preferredSize.height : 300
        panel.setContentSize(NSSize(width: width, height: height))

        panel.contentViewController = viewController
        centerPanel(panel)
        panel.makeKeyAndOrderFront(nil)

        openPanels[slot.id] = panel
        observeClose(panel: panel, slotID: slot.id)
    }

    private func openFallbackPanel(for slot: AUPluginSlot, auAudioUnit: AUAudioUnit?) {
        let panel = makePanel(title: slot.displayName)
        panel.setContentSize(NSSize(width: 360, height: 320))

        if let audioUnit = auAudioUnit {
            let rootView = GenericAUParameterView(audioUnit: audioUnit)
            panel.contentView = NSHostingView(rootView: rootView)
        } else {
            let rootView = VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Plugin not loaded")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            panel.contentView = NSHostingView(rootView: rootView)
        }

        centerPanel(panel)
        panel.makeKeyAndOrderFront(nil)

        openPanels[slot.id] = panel
        observeClose(panel: panel, slotID: slot.id)
    }

    // MARK: - Helpers

    private func makePanel(title: String) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        return panel
    }

    private func centerPanel(_ panel: NSPanel) {
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let pw = panel.frame.width
            let ph = panel.frame.height
            panel.setFrameOrigin(NSPoint(x: sf.midX - pw / 2, y: sf.midY - ph / 2))
        }
    }

    private func observeClose(panel: NSPanel, slotID: UUID) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.openPanels.removeValue(forKey: slotID)
        }
    }
}
