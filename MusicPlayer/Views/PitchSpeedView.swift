import SwiftUI

struct PitchSpeedView: View {
    @ObservedObject var pitchSpeed = PitchSpeedManager.shared

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Toggle("Pitch/Speed", isOn: $pitchSpeed.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()

                Text("Pitch / Speed")
                    .font(.headline)
                    .foregroundStyle(pitchSpeed.isEnabled ? .primary : .secondary)

                Spacer()

                Button("Reset") { pitchSpeed.reset() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    HStack {
                        Text("Pitch")
                            .frame(width: 80, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Slider(value: $pitchSpeed.pitch, in: -2400...2400, step: 100)
                        Text(pitchSpeed.pitch == 0 ? "0 st" : String(format: "%+.0f st", pitchSpeed.pitch / 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 50)
                    }
                    Text("Semitones")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                VStack(spacing: 4) {
                    HStack {
                        Text("Speed")
                            .frame(width: 80, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Slider(value: $pitchSpeed.rate, in: 0.25...4.0, step: 0.05)
                        Text(String(format: "%.2fx", pitchSpeed.rate))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 50)
                    }
                    HStack(spacing: 8) {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                            Button(speed == 1.0 ? "1x" : String(format: "%.2gx", speed)) {
                                pitchSpeed.rate = Float(speed)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(abs(pitchSpeed.rate - Float(speed)) < 0.01 ? .accentColor : nil)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .opacity(pitchSpeed.isEnabled ? 1.0 : 0.4)
            .allowsHitTesting(pitchSpeed.isEnabled)

            Spacer()
        }
    }
}
