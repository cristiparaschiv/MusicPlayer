import Foundation
import AVFoundation
import Combine

class DelayManager: ObservableObject {
    static let shared = DelayManager()

    private var activeNodes: [ObjectIdentifier: AVAudioUnitDelay] = [:]
    private let nodesLock = NSLock()

    @Published var isEnabled: Bool = false {
        didSet {
            applyWetDryToNodes()
            UserDefaults.standard.set(isEnabled, forKey: Constants.UserDefaultsKeys.delayEnabled)
        }
    }

    @Published var delayTime: Double = 0.5 {
        didSet {
            nodesLock.lock()
            for node in activeNodes.values { node.delayTime = delayTime }
            nodesLock.unlock()
            UserDefaults.standard.set(delayTime, forKey: Constants.UserDefaultsKeys.delayTime)
        }
    }

    @Published var feedback: Float = 50 {
        didSet {
            nodesLock.lock()
            for node in activeNodes.values { node.feedback = feedback }
            nodesLock.unlock()
            UserDefaults.standard.set(Double(feedback), forKey: Constants.UserDefaultsKeys.delayFeedback)
        }
    }

    @Published var wetDryMix: Float = 20 {
        didSet {
            applyWetDryToNodes()
            UserDefaults.standard.set(Double(wetDryMix), forKey: Constants.UserDefaultsKeys.delayWetDryMix)
        }
    }

    @Published var lowPassCutoff: Float = 15000 {
        didSet {
            nodesLock.lock()
            for node in activeNodes.values { node.lowPassCutoff = lowPassCutoff }
            nodesLock.unlock()
            UserDefaults.standard.set(Double(lowPassCutoff), forKey: Constants.UserDefaultsKeys.delayLowPassCutoff)
        }
    }

    private init() { loadPersistedState() }

    func createNode(for engine: AVAudioEngine) -> AVAudioUnitDelay {
        let node = AVAudioUnitDelay()
        node.delayTime = delayTime
        node.feedback = feedback
        node.wetDryMix = isEnabled ? wetDryMix : 0
        node.lowPassCutoff = lowPassCutoff

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

    func reset() {
        delayTime = 0.5
        feedback = 50
        wetDryMix = 20
        lowPassCutoff = 15000
    }

    private func applyWetDryToNodes() {
        let effectiveMix: Float = isEnabled ? wetDryMix : 0
        nodesLock.lock()
        for node in activeNodes.values { node.wetDryMix = effectiveMix }
        nodesLock.unlock()
    }

    private func loadPersistedState() {
        isEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.delayEnabled)
        if let t = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.delayTime) as? Double { delayTime = t }
        if let f = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.delayFeedback) as? Double { feedback = Float(f) }
        if let m = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.delayWetDryMix) as? Double { wetDryMix = Float(m) }
        if let c = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.delayLowPassCutoff) as? Double { lowPassCutoff = Float(c) }
    }
}
