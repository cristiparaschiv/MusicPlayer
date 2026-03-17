import Foundation
import AVFoundation
import AudioToolbox

// MARK: - EffectSlotType

enum EffectSlotType: String, Codable {
    case eq
    case reverb
    case delay
    case timePitch
    case auPlugin
}

// MARK: - EffectSlot Protocol

protocol EffectSlot: AnyObject, Identifiable {
    var id: UUID { get }
    var slotType: EffectSlotType { get }
    var displayName: String { get }
    var manufacturer: String { get }
    var isBypassed: Bool { get set }

    /// Synchronously create and register a node for the given engine. Returns nil for async types (e.g. AU plugins).
    @discardableResult
    func createNode(for engine: AVAudioEngine) -> AVAudioNode?

    /// Remove and unregister the node for the given engine.
    func removeNode(for engine: AVAudioEngine)

    /// Return the already-created node for the given engine, if any.
    func node(for engine: AVAudioEngine) -> AVAudioNode?
}

// MARK: - BuiltInEffectSlot

final class BuiltInEffectSlot: EffectSlot {
    let id: UUID
    let slotType: EffectSlotType

    var displayName: String {
        switch slotType {
        case .eq:        return "Equalizer"
        case .reverb:    return "Reverb"
        case .delay:     return "Delay"
        case .timePitch: return "Pitch & Speed"
        case .auPlugin:  return "AU Plugin"
        }
    }

    var manufacturer: String { return "Built-in" }

    var isBypassed: Bool {
        get {
            switch slotType {
            case .eq:        return !EQManager.shared.isEnabled
            case .reverb:    return !ReverbManager.shared.isEnabled
            case .delay:     return !DelayManager.shared.isEnabled
            case .timePitch: return !PitchSpeedManager.shared.isEnabled
            case .auPlugin:  return false
            }
        }
        set {
            switch slotType {
            case .eq:        EQManager.shared.isEnabled = !newValue
            case .reverb:    ReverbManager.shared.isEnabled = !newValue
            case .delay:     DelayManager.shared.isEnabled = !newValue
            case .timePitch: PitchSpeedManager.shared.isEnabled = !newValue
            case .auPlugin:  break
            }
        }
    }

    init(slotType: EffectSlotType) {
        precondition(slotType != .auPlugin, "Use AUPluginSlot for AU plugins")
        self.id = UUID()
        self.slotType = slotType
    }

    @discardableResult
    func createNode(for engine: AVAudioEngine) -> AVAudioNode? {
        switch slotType {
        case .eq:        return EQManager.shared.createEQNode(for: engine)
        case .reverb:    return ReverbManager.shared.createNode(for: engine)
        case .delay:     return DelayManager.shared.createNode(for: engine)
        case .timePitch: return PitchSpeedManager.shared.createNode(for: engine)
        case .auPlugin:  return nil
        }
    }

    func removeNode(for engine: AVAudioEngine) {
        switch slotType {
        case .eq:        EQManager.shared.removeEQNode(for: engine)
        case .reverb:    ReverbManager.shared.removeNode(for: engine)
        case .delay:     DelayManager.shared.removeNode(for: engine)
        case .timePitch: PitchSpeedManager.shared.removeNode(for: engine)
        case .auPlugin:  break
        }
    }

    func node(for engine: AVAudioEngine) -> AVAudioNode? {
        switch slotType {
        case .eq:        return EQManager.shared.node(for: engine)
        case .reverb:    return ReverbManager.shared.node(for: engine)
        case .delay:     return DelayManager.shared.node(for: engine)
        case .timePitch: return PitchSpeedManager.shared.node(for: engine)
        case .auPlugin:  return nil
        }
    }
}

// MARK: - AUPluginSlot

final class AUPluginSlot: EffectSlot {
    let id: UUID
    let slotType: EffectSlotType = .auPlugin

    let componentDescription: AudioComponentDescription
    let componentName: String
    let manufacturerName: String

    var isBypassed: Bool = false {
        didSet {
            let bypassed = isBypassed
            nodesLock.lock()
            let nodes = activeNodes.values.map { $0 }
            nodesLock.unlock()
            for node in nodes {
                node.auAudioUnit.shouldBypassEffect = bypassed
            }
        }
    }

    var savedState: [String: Any]?

    private var activeNodes: [ObjectIdentifier: AVAudioUnit] = [:]
    private let nodesLock = NSLock()

    var displayName: String { componentName }
    var manufacturer: String { manufacturerName }

    init(componentDescription: AudioComponentDescription, componentName: String, manufacturerName: String) {
        self.id = UUID()
        self.componentDescription = componentDescription
        self.componentName = componentName
        self.manufacturerName = manufacturerName
    }

    /// Always returns nil — AU instantiation is asynchronous. Use `createNodeAsync(for:completion:)`.
    @discardableResult
    func createNode(for engine: AVAudioEngine) -> AVAudioNode? {
        return nil
    }

    /// Asynchronously instantiate the AU, apply saved state, and register it for the given engine.
    func createNodeAsync(for engine: AVAudioEngine, completion: @escaping (AVAudioUnit?) -> Void) {
        AVAudioUnit.instantiate(with: componentDescription, options: []) { [weak self] audioUnit, error in
            guard let self = self, let audioUnit = audioUnit, error == nil else {
                completion(nil)
                return
            }

            // Apply saved state if available
            if let savedState = self.savedState {
                audioUnit.auAudioUnit.fullState = savedState
            }

            // Apply current bypass state
            audioUnit.auAudioUnit.shouldBypassEffect = self.isBypassed

            let key = ObjectIdentifier(engine)
            self.nodesLock.lock()
            self.activeNodes[key] = audioUnit
            self.nodesLock.unlock()

            completion(audioUnit)
        }
    }

    func removeNode(for engine: AVAudioEngine) {
        let key = ObjectIdentifier(engine)
        nodesLock.lock()
        activeNodes.removeValue(forKey: key)
        nodesLock.unlock()
    }

    func node(for engine: AVAudioEngine) -> AVAudioNode? {
        let key = ObjectIdentifier(engine)
        nodesLock.lock()
        defer { nodesLock.unlock() }
        return activeNodes[key]
    }

    /// Returns the AUAudioUnit for the given engine's node, if available.
    func audioUnit(for engine: AVAudioEngine) -> AUAudioUnit? {
        let key = ObjectIdentifier(engine)
        nodesLock.lock()
        defer { nodesLock.unlock() }
        return activeNodes[key]?.auAudioUnit
    }

    /// Returns the AUAudioUnit from any active engine (for UI when specific engine is unknown).
    var anyAudioUnit: AUAudioUnit? {
        nodesLock.lock()
        defer { nodesLock.unlock() }
        return activeNodes.values.first?.auAudioUnit
    }

    /// Captures the current full state from the first active node (for persistence).
    func captureState() -> [String: Any]? {
        nodesLock.lock()
        let firstNode = activeNodes.values.first
        nodesLock.unlock()
        return firstNode?.auAudioUnit.fullState
    }
}
