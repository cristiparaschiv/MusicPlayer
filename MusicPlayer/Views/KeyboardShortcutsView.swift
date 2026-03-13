import SwiftUI

struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    shortcutSection("Playback") {
                        shortcutRow("Play / Pause", keys: "Space")
                        shortcutRow("Next Track", keys: "Cmd + Right")
                        shortcutRow("Previous Track", keys: "Cmd + Left")
                        shortcutRow("Volume Up", keys: "Cmd + Up")
                        shortcutRow("Volume Down", keys: "Cmd + Down")
                    }

                    shortcutSection("Navigation") {
                        shortcutRow("Search", keys: "Cmd + F")
                        shortcutRow("Toggle Queue", keys: "Cmd + Shift + U")
                        shortcutRow("Settings", keys: "Cmd + ,")
                    }

                    shortcutSection("Views") {
                        shortcutRow("Immersive Mode", keys: "Cmd + Shift + F")
                        shortcutRow("Mini Player", keys: "Cmd + Shift + M")
                        shortcutRow("Audio Effects", keys: "Cmd + Shift + E")
                    }

                    shortcutSection("Immersive Mode") {
                        shortcutRow("Exit", keys: "ESC")
                        shortcutRow("Play / Pause", keys: "Space")
                        shortcutRow("Seek Forward 10s", keys: "Right Arrow")
                        shortcutRow("Seek Back 10s", keys: "Left Arrow")
                    }

                    shortcutSection("Library") {
                        shortcutRow("Show Shortcuts", keys: "Cmd + /")
                    }
                }
                .padding()
            }
        }
        .frame(width: 420, height: 500)
    }

    private func shortcutSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 2)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func shortcutRow(_ action: String, keys: String) -> some View {
        HStack {
            Text(action)
                .font(.subheadline)
            Spacer()
            Text(keys)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
        }
    }
}
