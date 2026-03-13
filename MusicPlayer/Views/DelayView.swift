import SwiftUI

struct DelayView: View {
    @ObservedObject var delay = DelayManager.shared

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Toggle("Delay", isOn: $delay.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()

                Text("Delay")
                    .font(.headline)
                    .foregroundStyle(delay.isEnabled ? .primary : .secondary)

                Spacer()

                Button("Reset") { delay.reset() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            VStack(spacing: 12) {
                HStack {
                    Text("Time")
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Slider(value: $delay.delayTime, in: 0...2, step: 0.01)
                    Text(String(format: "%.2fs", delay.delayTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 50)
                }

                HStack {
                    Text("Feedback")
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Slider(value: $delay.feedback, in: -100...100)
                    Text("\(Int(delay.feedback))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 50)
                }

                HStack {
                    Text("Mix")
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Slider(value: $delay.wetDryMix, in: 0...100)
                    Text("\(Int(delay.wetDryMix))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 50)
                }

                HStack {
                    Text("LP Cutoff")
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Slider(value: $delay.lowPassCutoff, in: 10...22050)
                    Text(delay.lowPassCutoff >= 1000 ? String(format: "%.1fkHz", delay.lowPassCutoff / 1000) : String(format: "%.0fHz", delay.lowPassCutoff))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 55)
                }
            }
            .padding(.horizontal, 20)
            .opacity(delay.isEnabled ? 1.0 : 0.4)
            .allowsHitTesting(delay.isEnabled)

            Spacer()
        }
    }
}
