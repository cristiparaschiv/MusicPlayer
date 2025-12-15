import SwiftUI
import AppKit

/// A view modifier that enables double-click detection for SwiftUI Tables on macOS.
///
/// This works by overlaying a transparent NSView that captures mouse down events
/// and properly detects double-clicks using NSEvent's clickCount property.
struct TableDoubleClickModifier: ViewModifier {
    let onDoubleClick: () -> Void

    func body(content: Content) -> some View {
        content
            .background(
                DoubleClickCaptureView(onDoubleClick: onDoubleClick)
            )
    }
}

/// NSViewRepresentable that captures and detects double-clicks
private struct DoubleClickCaptureView: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> ClickCaptureNSView {
        let view = ClickCaptureNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ClickCaptureNSView, context: Context) {
        nsView.coordinator = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleClick: onDoubleClick)
    }

    class Coordinator {
        let onDoubleClick: () -> Void

        init(onDoubleClick: @escaping () -> Void) {
            self.onDoubleClick = onDoubleClick
        }
    }
}

/// Custom NSView that intercepts mouse clicks and detects double-clicks
private class ClickCaptureNSView: NSView {
    weak var coordinator: DoubleClickCaptureView.Coordinator?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            setupEventMonitoring()
        } else {
            removeEventMonitoring()
        }
    }

    private func setupEventMonitoring() {
        // Monitor for mouse down events within our window
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return event }

            // Check if the click is within our view's bounds
            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)

            if self.bounds.contains(locationInView) && event.clickCount == 2 {
                // This is a double-click within our table
                DispatchQueue.main.async {
                    self.coordinator?.onDoubleClick()
                }
            }

            return event  // Always pass the event through so table selection works
        }
    }

    private func removeEventMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    deinit {
        removeEventMonitoring()
    }
}

// MARK: - View Extension for Easy Usage

extension View {
    /// Adds double-click detection to a SwiftUI Table view.
    ///
    /// Usage:
    /// ```swift
    /// Table(data, selection: $selection) {
    ///     // columns...
    /// }
    /// .onTableDoubleClick {
    ///     // Handle double-click
    /// }
    /// ```
    func onTableDoubleClick(perform action: @escaping () -> Void) -> some View {
        self.modifier(TableDoubleClickModifier(onDoubleClick: action))
    }
}
