import SwiftUI

struct ReverbView: View {
    @ObservedObject var reverb = ReverbManager.shared

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Toggle("Reverb", isOn: $reverb.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()

                Text("Reverb")
                    .font(.headline)
                    .foregroundStyle(reverb.isEnabled ? .primary : .secondary)

                Spacer()

                Button("Reset") { reverb.reset() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            VStack(spacing: 16) {
                HStack {
                    Text("Type")
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $reverb.presetIndex) {
                        ForEach(ReverbManager.presetNames, id: \.index) { item in
                            Text(item.name).tag(item.index)
                        }
                    }
                    .frame(width: 180)
                }

                HStack {
                    Text("Mix")
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Slider(value: $reverb.wetDryMix, in: 0...100)
                        .frame(maxWidth: .infinity)
                    Text("\(Int(reverb.wetDryMix))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40)
                }
            }
            .padding(.horizontal, 20)
            .opacity(reverb.isEnabled ? 1.0 : 0.4)
            .allowsHitTesting(reverb.isEnabled)

            Spacer()
        }
    }
}
