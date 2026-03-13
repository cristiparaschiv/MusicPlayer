import SwiftUI

struct AudioEffectsView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            EQView()
                .tabItem { Label("Equalizer", systemImage: "slider.vertical.3") }
                .tag(0)

            ReverbView()
                .tabItem { Label("Reverb", systemImage: "waveform.path") }
                .tag(1)

            DelayView()
                .tabItem { Label("Delay", systemImage: "repeat") }
                .tag(2)

            PitchSpeedView()
                .tabItem { Label("Pitch/Speed", systemImage: "metronome") }
                .tag(3)

            AudioEffectsPresetsView()
                .tabItem { Label("Presets", systemImage: "list.bullet") }
                .tag(4)
        }
        .frame(width: 520, height: 380)
    }
}

struct AudioEffectsPresetsView: View {
    @ObservedObject var presetManager = AudioEffectsPresetManager.shared
    @State private var showingSaveAlert = false
    @State private var newPresetName = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Combined Presets")
                    .font(.headline)

                Spacer()

                Button("Save Current") { showingSaveAlert = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            List {
                Section("Built-in") {
                    ForEach(AudioEffectsPreset.builtIn) { preset in
                        presetRow(preset)
                    }
                }

                if !presetManager.customPresets.isEmpty {
                    Section("Custom") {
                        ForEach(presetManager.customPresets) { preset in
                            presetRow(preset)
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        presetManager.deleteCustomPreset(preset)
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .alert("Save Preset", isPresented: $showingSaveAlert) {
            TextField("Preset name", text: $newPresetName)
            Button("Cancel", role: .cancel) { newPresetName = "" }
            Button("Save") {
                let name = newPresetName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { presetManager.saveCustomPreset(name: name) }
                newPresetName = ""
            }
            .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Save current effect settings as a preset")
        }
    }

    private func presetRow(_ preset: AudioEffectsPreset) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                HStack(spacing: 6) {
                    if preset.eqEnabled { effectBadge("EQ") }
                    if preset.reverbEnabled { effectBadge("Reverb") }
                    if preset.delayEnabled { effectBadge("Delay") }
                    if preset.pitchSpeedEnabled { effectBadge("Pitch") }
                }
            }

            Spacer()

            if presetManager.selectedPresetId == preset.id {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { presetManager.applyPreset(preset) }
    }

    private func effectBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.15))
            .foregroundColor(.accentColor)
            .cornerRadius(3)
    }
}
