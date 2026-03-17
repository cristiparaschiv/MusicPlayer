import SwiftUI

struct AudioEffectsView: View {
    @State private var expandedSlotIndex: Int? = nil

    var body: some View {
        HSplitView {
            // Left: Effect chain
            EffectChainView(expandedSlotIndex: $expandedSlotIndex)
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)

            // Right: Detail panel
            detailPane
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 400)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let index = expandedSlotIndex,
           let slot = EffectChainManager.shared.slots[index] {
            switch slot.slotType {
            case .eq:
                EQView()
            case .reverb:
                ReverbView()
            case .delay:
                DelayView()
            case .timePitch:
                PitchSpeedView()
            case .auPlugin:
                auPluginPlaceholder
            }
        } else {
            emptyDetailPlaceholder
        }
    }

    private var emptyDetailPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Select an effect slot")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var auPluginPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "puzzlepiece")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Open floating panel to edit")
                .foregroundStyle(.secondary)
                .font(.callout)
            Text("Click the plugin slot to open its UI window")
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
