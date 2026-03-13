import Foundation
import Combine

class AudioEffectsPresetManager: ObservableObject {
    static let shared = AudioEffectsPresetManager()

    @Published var customPresets: [AudioEffectsPreset] = []
    @Published var selectedPresetId: String?

    var allPresets: [AudioEffectsPreset] {
        AudioEffectsPreset.builtIn + customPresets
    }

    private init() { loadPersistedState() }

    func applyPreset(_ preset: AudioEffectsPreset) {
        selectedPresetId = preset.id
        preset.apply()
        UserDefaults.standard.set(preset.id, forKey: Constants.UserDefaultsKeys.audioEffectsSelectedPresetId)
    }

    func saveCustomPreset(name: String) {
        let id = "custom_fx_\(UUID().uuidString)"
        let preset = AudioEffectsPreset.captureCurrentState(id: id, name: name)
        customPresets.append(preset)
        selectedPresetId = id
        persistCustomPresets()
    }

    func deleteCustomPreset(_ preset: AudioEffectsPreset) {
        customPresets.removeAll { $0.id == preset.id }
        if selectedPresetId == preset.id { selectedPresetId = nil }
        persistCustomPresets()
    }

    func clearSelection() {
        selectedPresetId = nil
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.audioEffectsSelectedPresetId)
    }

    private func persistCustomPresets() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: Constants.UserDefaultsKeys.audioEffectsPresets)
        }
    }

    private func loadPersistedState() {
        if let data = UserDefaults.standard.data(forKey: Constants.UserDefaultsKeys.audioEffectsPresets),
           let saved = try? JSONDecoder().decode([AudioEffectsPreset].self, from: data) {
            customPresets = saved
        }
        selectedPresetId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.audioEffectsSelectedPresetId)
    }
}
