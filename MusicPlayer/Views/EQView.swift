import SwiftUI

struct EQView: View {
    @ObservedObject var eq = EQManager.shared
    @State private var showingSaveAlert = false
    @State private var customPresetName = ""

    var body: some View {
        VStack(spacing: 16) {
            // Top bar
            HStack(spacing: 12) {
                Toggle("EQ", isOn: $eq.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()

                Text("EQ")
                    .font(.headline)
                    .foregroundStyle(eq.isEnabled ? .primary : .secondary)

                Spacer()

                Picker("Preset", selection: Binding(
                    get: { eq.selectedPreset?.id ?? "" },
                    set: { id in
                        if let preset = eq.allPresets.first(where: { $0.id == id }) {
                            eq.applyPreset(preset)
                        }
                    }
                )) {
                    Text("Custom").tag("")
                    Divider()
                    ForEach(EQPreset.builtIn) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                    if !eq.customPresets.isEmpty {
                        Divider()
                        ForEach(eq.customPresets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                }
                .frame(width: 140)

                Button("Save") {
                    showingSaveAlert = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Reset") {
                    eq.reset()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            // dB scale + sliders
            HStack(alignment: .top, spacing: 0) {
                // dB labels
                VStack {
                    Text("+12")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("0 dB")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("-12")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 32, height: 180)

                // 10 band sliders
                ForEach(0..<EQPreset.bandCount, id: \.self) { i in
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack {
                                // Track background
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(width: 4)

                                // Center line (0 dB)
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.3))
                                    .frame(width: 14, height: 1)

                                // Fill from center to thumb
                                let normalizedGain = CGFloat(eq.gains[i] - EQPreset.minGain) / CGFloat(EQPreset.maxGain - EQPreset.minGain)
                                let thumbY = (1.0 - normalizedGain) * (geo.size.height - 14) + 7
                                let centerY = geo.size.height / 2

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(eq.isEnabled ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.2))
                                    .frame(width: 4, height: abs(thumbY - centerY))
                                    .position(x: geo.size.width / 2, y: (thumbY + centerY) / 2)

                                // Thumb
                                Circle()
                                    .fill(eq.isEnabled ? Color.accentColor : Color.secondary)
                                    .frame(width: 14, height: 14)
                                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                                    .position(x: geo.size.width / 2, y: thumbY)
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                let clamped = min(max(value.location.y, 7), geo.size.height - 7)
                                                let normalized = 1.0 - ((clamped - 7) / (geo.size.height - 14))
                                                let gain = Float(normalized) * (EQPreset.maxGain - EQPreset.minGain) + EQPreset.minGain
                                                eq.setGain(gain, forBand: i)
                                            }
                                    )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: 180)

                        // Gain value
                        Text(String(format: "%+.0f", eq.gains[i]))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(height: 12)

                        // Frequency label
                        Text(EQPreset.bandLabels[i])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .opacity(eq.isEnabled ? 1.0 : 0.4)
            .allowsHitTesting(eq.isEnabled)

            Spacer(minLength: 8)
        }
        .frame(width: 480, height: 300)
        .alert("Save Preset", isPresented: $showingSaveAlert) {
            TextField("Preset name", text: $customPresetName)
            Button("Cancel", role: .cancel) {
                customPresetName = ""
            }
            Button("Save") {
                let name = customPresetName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    eq.saveCustomPreset(name: name)
                }
                customPresetName = ""
            }
            .disabled(customPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Enter a name for your custom preset")
        }
    }
}
