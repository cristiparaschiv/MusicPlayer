import SwiftUI

struct ScriptsView: View {
    @ObservedObject private var engine = ScriptingEngine.shared

    var body: some View {
        VStack(spacing: 0) {
            if engine.scripts.isEmpty {
                emptyState
            } else {
                scriptList
            }

            Divider()

            HStack {
                Button("Open Scripts Folder") {
                    engine.openScriptsFolder()
                }

                Spacer()

                Button("Script Console") {
                    NotificationCenter.default.post(
                        name: Constants.Notifications.scriptConsoleToggle,
                        object: nil
                    )
                }
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "applescript")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Scripts")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Add .js files to the Scripts folder to get started.")
                .font(.body)
                .foregroundStyle(.tertiary)
            Button("Open Scripts Folder") {
                engine.openScriptsFolder()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var scriptList: some View {
        List {
            ForEach(engine.scripts) { script in
                ScriptRowView(script: script)
            }
        }
    }
}

struct ScriptRowView: View {
    let script: ScriptMetadata
    @ObservedObject private var engine = ScriptingEngine.shared

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { script.isEnabled },
                set: { _ in engine.toggleScript(id: script.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(script.name)
                        .font(.body)
                        .fontWeight(.medium)

                    statusIndicator
                }

                if !script.description.isEmpty {
                    Text(script.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !script.author.isEmpty {
                    Text("by \(script.author)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let event = script.event {
                Text(event)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }

            if script.event == nil {
                Button {
                    engine.runScript(id: script.id)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(!script.isEnabled)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch script.status {
        case .idle:
            EmptyView()
        case .running:
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}
