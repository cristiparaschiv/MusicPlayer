import Foundation
import AVFoundation
import Combine

class PitchSpeedManager: ObservableObject {
    static let shared = PitchSpeedManager()

    private var activeNodes: [ObjectIdentifier: AVAudioUnitTimePitch] = [:]
    private let nodesLock = NSLock()

    @Published var isEnabled: Bool = false {
        didSet {
            applyValuesToNodes()
            UserDefaults.standard.set(isEnabled, forKey: Constants.UserDefaultsKeys.pitchSpeedEnabled)
        }
    }

    @Published var pitch: Float = 0 {
        didSet {
            applyValuesToNodes()
            UserDefaults.standard.set(Double(pitch), forKey: Constants.UserDefaultsKeys.pitchValue)
        }
    }

    @Published var rate: Float = 1.0 {
        didSet {
            applyValuesToNodes()
            UserDefaults.standard.set(Double(rate), forKey: Constants.UserDefaultsKeys.rateValue)
        }
    }

    private init() { loadPersistedState() }

    func createNode(for engine: AVAudioEngine) -> AVAudioUnitTimePitch {
        let node = AVAudioUnitTimePitch()
        node.pitch = isEnabled ? pitch : 0
        node.rate = isEnabled ? rate : 1.0

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

    /// Returns the active time pitch node for the given engine, if one exists.
    func node(for engine: AVAudioEngine) -> AVAudioNode? {
        let key = ObjectIdentifier(engine)
        nodesLock.lock()
        defer { nodesLock.unlock() }
        return activeNodes[key]
    }

    func reset() {
        pitch = 0
        rate = 1.0
    }

    private func applyValuesToNodes() {
        let effectivePitch: Float = isEnabled ? pitch : 0
        let effectiveRate: Float = isEnabled ? rate : 1.0
        nodesLock.lock()
        for node in activeNodes.values {
            node.pitch = effectivePitch
            node.rate = effectiveRate
        }
        nodesLock.unlock()
    }

    private func loadPersistedState() {
        isEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.pitchSpeedEnabled)
        if let p = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.pitchValue) as? Double { pitch = Float(p) }
        if let r = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.rateValue) as? Double { rate = Float(r) }
    }
}
