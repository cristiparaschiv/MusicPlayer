import Foundation
import AVFoundation
import Combine

class EQManager: ObservableObject {
    static let shared = EQManager()

    // MARK: - Active EQ Nodes

    private var activeNodes: [ObjectIdentifier: AVAudioUnitEQ] = [:]
    private let nodesLock = NSLock()

    // MARK: - Published State

    @Published var isEnabled: Bool = false {
        didSet {
            nodesLock.lock()
            for node in activeNodes.values {
                node.bypass = !isEnabled
            }
            nodesLock.unlock()
            UserDefaults.standard.set(isEnabled, forKey: Constants.UserDefaultsKeys.eqEnabled)
        }
    }

    @Published var gains: [Float] = Array(repeating: 0, count: EQPreset.bandCount) {
        didSet {
            applyGains()
            persistGains()
        }
    }

    @Published var selectedPreset: EQPreset? = EQPreset.flat {
        didSet {
            UserDefaults.standard.set(selectedPreset?.id, forKey: Constants.UserDefaultsKeys.eqSelectedPresetId)
        }
    }

    @Published var customPresets: [EQPreset] = []

    var allPresets: [EQPreset] {
        EQPreset.builtIn + customPresets
    }

    // MARK: - Init

    private init() {
        loadPersistedState()
    }

    // MARK: - Node Management

    /// Creates a new EQ node configured with current settings, for insertion into an audio engine.
    func createEQNode(for engine: AVAudioEngine) -> AVAudioUnitEQ {
        let node = AVAudioUnitEQ(numberOfBands: EQPreset.bandCount)

        for i in 0..<EQPreset.bandCount {
            let band = node.bands[i]
            band.filterType = .parametric
            band.frequency = EQPreset.frequencies[i]
            band.bandwidth = 1.0
            band.gain = gains[i]
            band.bypass = false
        }

        node.bypass = !isEnabled

        let key = ObjectIdentifier(engine)
        nodesLock.lock()
        activeNodes[key] = node
        nodesLock.unlock()

        return node
    }

    /// Removes tracking for an engine's EQ node (call when player is disposed).
    func removeEQNode(for engine: AVAudioEngine) {
        let key = ObjectIdentifier(engine)
        nodesLock.lock()
        activeNodes.removeValue(forKey: key)
        nodesLock.unlock()
    }

    // MARK: - Public API

    func setGain(_ gain: Float, forBand band: Int) {
        guard band >= 0, band < EQPreset.bandCount else { return }
        gains[band] = min(max(gain, EQPreset.minGain), EQPreset.maxGain)
        selectedPreset = nil
    }

    func applyPreset(_ preset: EQPreset) {
        guard preset.gains.count == EQPreset.bandCount else { return }
        selectedPreset = preset
        gains = preset.gains
    }

    func reset() {
        applyPreset(EQPreset.flat)
    }

    func saveCustomPreset(name: String) {
        let id = "custom_\(UUID().uuidString)"
        let preset = EQPreset(id: id, name: name, gains: gains, isBuiltIn: false)
        customPresets.append(preset)
        selectedPreset = preset
        persistCustomPresets()
    }

    func deleteCustomPreset(_ preset: EQPreset) {
        customPresets.removeAll { $0.id == preset.id }
        if selectedPreset?.id == preset.id {
            selectedPreset = nil
        }
        persistCustomPresets()
    }

    // MARK: - Private

    private func applyGains() {
        nodesLock.lock()
        for node in activeNodes.values {
            for i in 0..<min(gains.count, EQPreset.bandCount) {
                node.bands[i].gain = gains[i]
            }
        }
        nodesLock.unlock()
    }

    private func persistGains() {
        let gainsData = gains.map { Double($0) }
        UserDefaults.standard.set(gainsData, forKey: Constants.UserDefaultsKeys.eqGains)
    }

    private func persistCustomPresets() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: Constants.UserDefaultsKeys.eqCustomPresets)
        }
    }

    private func loadPersistedState() {
        isEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.eqEnabled)

        if let data = UserDefaults.standard.data(forKey: Constants.UserDefaultsKeys.eqCustomPresets),
           let saved = try? JSONDecoder().decode([EQPreset].self, from: data) {
            customPresets = saved
        }

        if let savedGains = UserDefaults.standard.array(forKey: Constants.UserDefaultsKeys.eqGains) as? [Double] {
            gains = savedGains.map { Float($0) }
        }

        if let presetId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.eqSelectedPresetId) {
            selectedPreset = allPresets.first { $0.id == presetId }
        }
    }
}
