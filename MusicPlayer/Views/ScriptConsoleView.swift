import SwiftUI
import AppKit

// MARK: - Script Console Window Manager

final class ScriptConsoleWindowManager {
    static let shared = ScriptConsoleWindowManager()

    private var panel: NSPanel?

    private init() {
        NotificationCenter.default.addObserver(
            forName: Constants.Notifications.scriptConsoleToggle,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.toggle()
        }
    }

    func toggle() {
        if let panel = panel, panel.isVisible {
            panel.close()
        } else {
            show()
        }
    }

    private func show() {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Script Console"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let contentView = ScriptConsoleView()
        panel.contentView = NSHostingView(rootView: contentView)

        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: sf.maxX - 620,
                y: sf.minY + 20
            ))
        }

        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

// MARK: - Script Console View

struct ScriptConsoleView: View {
    @ObservedObject private var console = ScriptConsoleManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(console.entries) { entry in
                            ConsoleEntryView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: console.entries.count) { _ in
                    if let last = console.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack {
                Text("\(console.entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    console.clear()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 400, minHeight: 200)
    }
}

struct ConsoleEntryView: View {
    let entry: ConsoleEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: entry.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)

            levelIcon

            Text(entry.scriptName)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(messageColor)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var levelIcon: some View {
        switch entry.level {
        case .log:
            Image(systemName: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .warn:
            Image(systemName: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.yellow)
        case .error:
            Image(systemName: "xmark.circle")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private var messageColor: Color {
        switch entry.level {
        case .log: return .primary
        case .warn: return .yellow
        case .error: return .red
        }
    }
}
