import Foundation
import AVFoundation
import Combine

class ReverbManager: ObservableObject {
    static let shared = ReverbManager()

    private var activeNodes: [ObjectIdentifier: AVAudioUnitReverb] = [:]
    private let nodesLock = NSLock()

    static let presetNames: [(index: Int, name: String)] = [
        (0, "Small Room"), (1, "Medium Room"), (2, "Large Room"), (3, "Medium Hall"),
        (4, "Large Hall"), (5, "Plate"), (6, "Medium Chamber"), (7, "Large Chamber"),
        (8, "Cathedral"), (9, "Large Room 2"), (10, "Medium Hall 2"), (11, "Medium Hall 3"),
        (12, "Large Hall 2")
    ]

    @Published var isEnabled: Bool = false {
        didSet {
            applyWetDryToNodes()
            UserDefaults.standard.set(isEnabled, forKey: Constants.UserDefaultsKeys.reverbEnabled)
        }
    }

    @Published var presetIndex: Int = 0 {
        didSet {
            applyPresetToNodes()
            UserDefaults.standard.set(presetIndex, forKey: Constants.UserDefaultsKeys.reverbPresetIndex)
        }
    }

    @Published var wetDryMix: Float = 25 {
        didSet {
            applyWetDryToNodes()
            UserDefaults.standard.set(Double(wetDryMix), forKey: Constants.UserDefaultsKeys.reverbWetDryMix)
        }
    }

    private init() { loadPersistedState() }

    func createNode(for engine: AVAudioEngine) -> AVAudioUnitReverb {
        let node = AVAudioUnitReverb()
        if let preset = AVAudioUnitReverbPreset(rawValue: presetIndex) {
            node.loadFactoryPreset(preset)
        }
        node.wetDryMix = isEnabled ? wetDryMix : 0

        let key = ObjectIdentifier(engine)
        nodesLock.lock()
        activeNodes[key] = node
        nodesLock.unlock()
        return node
    }

    func removeNode(for engine: AVAudioEngine) {
        let key = ObjectIdentifier(engine)
        nodesLock.lock()
        activeNodes.removeValue(forKey: key)
        nodesLock.unlock()
    }

    /// Returns the active reverb node for the given engine, if one exists.
    func node(for engine: AVAudioEngine) -> AVAudioNode? {
        let key = ObjectIdentifier(engine)
        nodesLock.lock()
        defer { nodesLock.unlock() }
        return activeNodes[key]
    }

    func reset() {
        presetIndex = 0
        wetDryMix = 25
    }

    private func applyWetDryToNodes() {
        let effectiveMix: Float = isEnabled ? wetDryMix : 0
        nodesLock.lock()
        for node in activeNodes.values { node.wetDryMix = effectiveMix }
        nodesLock.unlock()
    }

    private func applyPresetToNodes() {
        guard let preset = AVAudioUnitReverbPreset(rawValue: presetIndex) else { return }
        nodesLock.lock()
        for node in activeNodes.values { node.loadFactoryPreset(preset) }
        nodesLock.unlock()
    }

    private func loadPersistedState() {
        isEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.reverbEnabled)
        presetIndex = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKeys.reverbPresetIndex)
        if let mix = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.reverbWetDryMix) as? Double {
            wetDryMix = Float(mix)
        }
    }
}
