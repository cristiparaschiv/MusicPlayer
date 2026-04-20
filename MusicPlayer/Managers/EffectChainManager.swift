import Foundation
import AVFoundation
import AudioToolbox
import Combine

// MARK: - EffectChainManager

final class EffectChainManager: ObservableObject {

    static let shared = EffectChainManager()

    // MARK: - Published State

    @Published private(set) var slots: [EffectSlot?] = Array(repeating: nil, count: EffectChainConfig.slotCount)

    // MARK: - Engine Tracking

    /// All active engines (one per AudioPlayer instance).
    private var activeEngines: [AVAudioEngine] = []

    /// Weak-reference wrappers for each engine (engines are owned by AudioPlayer).
    private let lock = NSLock()

    // MARK: - Init

    private init() {
        loadConfig()
    }

    // MARK: - Config Load / Save

    func loadConfig() {
        let config = EffectChainConfig.load()
        var newSlots: [EffectSlot?] = []

        for (index, slotConfig) in config.slots.enumerated() {
            guard let sc = slotConfig else {
                newSlots.append(nil)
                continue
            }

            if sc.type == .auPlugin {
                // Reconstruct AUPluginSlot
                guard let typeCode = sc.auComponentType,
                      let subType = sc.auComponentSubType,
                      let mfr = sc.auComponentManufacturer else {
                    newSlots.append(nil)
                    continue
                }
                let desc = AudioComponentDescription(
                    componentType: typeCode,
                    componentSubType: subType,
                    componentManufacturer: mfr,
                    componentFlags: 0,
                    componentFlagsMask: 0
                )
                let slot = AUPluginSlot(
                    componentDescription: desc,
                    componentName: sc.auComponentName ?? "Unknown Plugin",
                    manufacturerName: sc.auComponentManufacturerName ?? "Unknown"
                )
                slot.isBypassed = sc.isBypassed

                // Load saved AU state from binary plist file
                if let stateFileName = sc.auStateFileName {
                    let stateURL = EffectChainConfig.pluginPresetsDirectory
                        .appendingPathComponent(stateFileName)
                    if let data = try? Data(contentsOf: stateURL),
                       let state = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                        slot.savedState = state
                    }
                }
                newSlots.append(slot)
            } else {
                let slot = BuiltInEffectSlot(slotType: sc.type)
                slot.isBypassed = sc.isBypassed
                newSlots.append(slot)
            }
        }

        // Pad to slotCount if needed
        while newSlots.count < EffectChainConfig.slotCount { newSlots.append(nil) }

        DispatchQueue.main.async {
            self.slots = newSlots
        }
    }

    func saveConfig() {
        lock.lock()
        let currentSlots = slots
        lock.unlock()

        var slotConfigs: [EffectChainConfig.SlotConfig?] = []

        try? FileManager.default.createDirectory(
            at: EffectChainConfig.pluginPresetsDirectory,
            withIntermediateDirectories: true
        )

        for slot in currentSlots {
            guard let slot = slot else {
                slotConfigs.append(nil)
                continue
            }

            if let auSlot = slot as? AUPluginSlot {
                let stateFileName: String?

                // Capture AU state as binary plist (AU fullState may contain Data values — JSON cannot encode those)
                if let state = auSlot.captureState() {
                    let fileName = "\(auSlot.id.uuidString).plist"
                    let fileURL = EffectChainConfig.pluginPresetsDirectory.appendingPathComponent(fileName)
                    if let data = try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0) {
                        try? data.write(to: fileURL, options: .atomic)
                        stateFileName = fileName
                    } else {
                        stateFileName = nil
                    }
                } else {
                    stateFileName = nil
                }

                let desc = auSlot.componentDescription
                slotConfigs.append(EffectChainConfig.SlotConfig(
                    type: .auPlugin,
                    isBypassed: auSlot.isBypassed,
                    auComponentType: desc.componentType,
                    auComponentSubType: desc.componentSubType,
                    auComponentManufacturer: desc.componentManufacturer,
                    auComponentName: auSlot.componentName,
                    auComponentManufacturerName: auSlot.manufacturerName,
                    auStateFileName: stateFileName
                ))
            } else {
                slotConfigs.append(EffectChainConfig.SlotConfig(
                    type: slot.slotType,
                    isBypassed: slot.isBypassed
                ))
            }
        }

        var config = EffectChainConfig(slots: slotConfigs)
        config.save()

        NotificationCenter.default.post(name: Constants.Notifications.effectChainChanged, object: nil)
    }

    // MARK: - Engine Registration

    func registerEngine(_ engine: AVAudioEngine) {
        lock.lock()
        if !activeEngines.contains(where: { $0 === engine }) {
            activeEngines.append(engine)
        }
        lock.unlock()
    }

    func unregisterEngine(_ engine: AVAudioEngine) {
        lock.lock()
        activeEngines.removeAll { $0 === engine }
        lock.unlock()
        teardownChain(for: engine)
    }

    // MARK: - Chain Building

    /// Synchronous chain build. Returns the entry node (first non-nil slot), or nil if no slots.
    /// Connects: sourceNode → Slot0 → … → SlotN → mainMixerNode
    /// NOTE: AU plugin slots are skipped (they require async instantiation). Use buildChainAsync when AU plugins are present.
    @discardableResult
    func buildChain(for engine: AVAudioEngine, sourceNode: AVAudioNode, format: AVAudioFormat) -> AVAudioNode? {
        lock.lock()
        let currentSlots = slots
        lock.unlock()

        let activeSlots = currentSlots.compactMap { $0 }.filter { !($0 is AUPluginSlot) }

        guard !activeSlots.isEmpty else {
            engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
            return nil
        }

        // Create and attach nodes
        var nodes: [AVAudioNode] = []
        for slot in activeSlots {
            if let node = slot.createNode(for: engine) {
                engine.attach(node)
                nodes.append(node)
            }
        }

        guard !nodes.isEmpty else {
            engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
            return nil
        }

        // Wire: source → first → … → last → mixer
        // Try connecting with the source format. If an AU effect doesn't support it
        // (e.g. hi-res 24-bit/96kHz), catch the ObjC exception and bypass the chain.
        do {
            try ObjCExceptionCatcher.try {
                engine.connect(sourceNode, to: nodes[0], format: format)
                for i in 0..<(nodes.count - 1) {
                    engine.connect(nodes[i], to: nodes[i + 1], format: format)
                }
                engine.connect(nodes.last!, to: engine.mainMixerNode, format: format)
            }
        } catch {
            #if DEBUG
            print("[EffectChain] Format not supported by effect nodes, bypassing chain: \(error)")
            #endif
            // Clean up: safely detach effect nodes (some may not have been attached)
            for node in nodes {
                _ = try? ObjCExceptionCatcher.try {
                    engine.disconnectNodeInput(node)
                    engine.disconnectNodeOutput(node)
                    engine.detach(node)
                }
            }
            // Also remove slot references so teardown doesn't try to detach them again
            for slot in activeSlots {
                slot.removeNode(for: engine)
            }
            engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
            return nil
        }

        return nodes[0]
    }

    /// Async chain build for chains that may contain AU plugins.
    func buildChainAsync(
        for engine: AVAudioEngine,
        sourceNode: AVAudioNode,
        format: AVAudioFormat,
        completion: @escaping (AVAudioNode?) -> Void
    ) {
        lock.lock()
        let currentSlots = slots
        lock.unlock()

        // Collect non-nil slots with their original indices (for ordering)
        let indexedSlots: [(index: Int, slot: EffectSlot)] = currentSlots
            .enumerated()
            .compactMap { idx, slot in slot.map { (idx, $0) } }
            .sorted { $0.index < $1.index }

        guard !indexedSlots.isEmpty else {
            engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
            completion(nil)
            return
        }

        // Build nodes array: some sync, some async
        var orderedNodes: [AVAudioNode?] = Array(repeating: nil, count: indexedSlots.count)
        let group = DispatchGroup()

        for (arrayIndex, item) in indexedSlots.enumerated() {
            if let auSlot = item.slot as? AUPluginSlot {
                group.enter()
                auSlot.createNodeAsync(for: engine) { audioUnit in
                    if let audioUnit = audioUnit {
                        engine.attach(audioUnit)
                        orderedNodes[arrayIndex] = audioUnit
                    }
                    group.leave()
                }
            } else {
                if let node = item.slot.createNode(for: engine) {
                    engine.attach(node)
                    orderedNodes[arrayIndex] = node
                }
            }
        }

        group.notify(queue: .main) {
            let nodes = orderedNodes.compactMap { $0 }

            guard !nodes.isEmpty else {
                engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
                completion(nil)
                return
            }

            do {
                try ObjCExceptionCatcher.try {
                    engine.connect(sourceNode, to: nodes[0], format: format)
                    for i in 0..<(nodes.count - 1) {
                        engine.connect(nodes[i], to: nodes[i + 1], format: format)
                    }
                    engine.connect(nodes.last!, to: engine.mainMixerNode, format: format)
                }
            } catch {
                #if DEBUG
                print("[EffectChain] Async: format not supported, bypassing chain: \(error)")
                #endif
                for node in nodes {
                    _ = try? ObjCExceptionCatcher.try {
                        engine.disconnectNodeInput(node)
                        engine.disconnectNodeOutput(node)
                        engine.detach(node)
                    }
                }
                engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
                completion(nil)
                return
            }

            completion(nodes[0])
        }
    }

    /// Remove all effect nodes for a disposed engine.
    func teardownChain(for engine: AVAudioEngine) {
        lock.lock()
        let currentSlots = slots
        lock.unlock()

        for slot in currentSlots.compactMap({ $0 }) {
            if let node = slot.node(for: engine) {
                _ = try? ObjCExceptionCatcher.try {
                    engine.disconnectNodeInput(node)
                    engine.disconnectNodeOutput(node)
                    engine.detach(node)
                }
            }
            slot.removeNode(for: engine)
        }
    }

    // MARK: - Slot Mutations

    /// Swaps two slots and rebuilds all chains.
    func move(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < EffectChainConfig.slotCount,
              destinationIndex >= 0, destinationIndex < EffectChainConfig.slotCount else { return }

        var newSlots = slots
        newSlots.swapAt(sourceIndex, destinationIndex)
        slots = newSlots  // Must be called on main thread (UI gesture origin)

        rebuildAllChains()
        saveConfig()
    }

    /// Insert a built-in effect at the given index.
    func insertBuiltIn(type slotType: EffectSlotType, at index: Int) {
        guard slotType != .auPlugin else { return }
        guard index >= 0, index < EffectChainConfig.slotCount else { return }

        let slot = BuiltInEffectSlot(slotType: slotType)

        var newSlots = slots
        newSlots[index] = slot
        slots = newSlots  // Must be called on main thread (UI gesture origin)

        rebuildAllChains()
        saveConfig()
    }

    /// Insert an AU plugin effect at the given index. Calls completion on the main queue when done.
    func insertAUPlugin(
        description: AudioComponentDescription,
        name: String,
        manufacturer: String,
        at index: Int,
        completion: @escaping () -> Void
    ) {
        guard index >= 0, index < EffectChainConfig.slotCount else {
            completion()
            return
        }

        let slot = AUPluginSlot(
            componentDescription: description,
            componentName: name,
            manufacturerName: manufacturer
        )

        var newSlots = slots
        newSlots[index] = slot
        slots = newSlots  // Must be called on main thread

        lock.lock()
        let engines = activeEngines
        lock.unlock()

        guard !engines.isEmpty else {
            saveConfig()
            completion()
            return
        }

        // Async rebuild needed for AU plugins
        let outerGroup = DispatchGroup()

        for engine in engines {
            outerGroup.enter()
            _teardownAndRebuildAsync(engine: engine) {
                outerGroup.leave()
            }
        }

        outerGroup.notify(queue: .main) { [weak self] in
            self?.saveConfig()
            completion()
        }
    }

    /// Remove the slot at index.
    func removeSlot(at index: Int) {
        guard index >= 0, index < EffectChainConfig.slotCount else { return }

        let removedSlot = slots[index]
        var newSlots = slots
        newSlots[index] = nil
        slots = newSlots  // Must be called on main thread

        lock.lock()
        let engines = activeEngines
        lock.unlock()

        // Remove nodes from all engines before rebuilding
        if let slot = removedSlot {
            for engine in engines {
                if let node = slot.node(for: engine) {
                    engine.disconnectNodeInput(node)
                    engine.disconnectNodeOutput(node)
                    engine.detach(node)
                }
                slot.removeNode(for: engine)
            }
        }

        rebuildAllChains()
        saveConfig()
    }

    /// Toggle bypass state for the slot at index.
    func toggleBypass(at index: Int) {
        guard index >= 0, index < EffectChainConfig.slotCount else { return }

        if let slot = slots[index] {
            objectWillChange.send()
            slot.isBypassed = !slot.isBypassed
        }

        saveConfig()
    }

    // MARK: - Private Rebuild

    private func hasAUPlugins() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return slots.contains { $0 is AUPluginSlot }
    }

    /// Disconnect, remove old nodes, then rebuild for all active engines.
    private func rebuildAllChains() {
        lock.lock()
        let engines = activeEngines
        lock.unlock()

        if hasAUPlugins() {
            let group = DispatchGroup()
            for engine in engines {
                group.enter()
                _teardownAndRebuildAsync(engine: engine) {
                    group.leave()
                }
            }
            // Fire and forget — caller (move/removeSlot) handles UI update
        } else {
            for engine in engines {
                _teardownAndRebuildSync(engine: engine)
            }
        }
    }

    /// Finds the source node at the start of the chain (the node SFBAudioEngine connected).
    /// Walks backward from mainMixer through any effect nodes to find the original source.
    private func findSourceNode(in engine: AVAudioEngine) -> (node: AVAudioNode, format: AVAudioFormat)? {
        let mixer = engine.mainMixerNode

        // Walk the connection chain backward from mixer to find the original source
        guard let firstConnection = engine.inputConnectionPoint(for: mixer, inputBus: 0),
              let firstNode = firstConnection.node else { return nil }

        // Walk backward: if this node is one of our effect nodes, keep going
        var current = firstNode
        var visited = Set<ObjectIdentifier>()

        while visited.insert(ObjectIdentifier(current)).inserted {
            // Check if this node belongs to any of our slots
            let isOurNode = slots.compactMap({ $0 }).contains { $0.node(for: engine) === current }
            if !isOurNode {
                // This is the source node (not one of ours)
                break
            }
            // Walk backward
            guard let cp = engine.inputConnectionPoint(for: current, inputBus: 0),
                  let prev = cp.node else { break }
            current = prev
        }

        let format = mixer.inputFormat(forBus: 0)
        return (current, format)
    }

    private func _teardownAndRebuildSync(engine: AVAudioEngine) {
        // Find source BEFORE disconnecting anything
        guard let (sourceNode, format) = findSourceNode(in: engine) else { return }

        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }

        // Disconnect and detach all our effect nodes
        let mixer = engine.mainMixerNode
        engine.disconnectNodeInput(mixer)

        lock.lock()
        let currentSlots = slots
        lock.unlock()

        for slot in currentSlots.compactMap({ $0 }) {
            if let node = slot.node(for: engine) {
                engine.disconnectNodeInput(node)
                engine.disconnectNodeOutput(node)
                engine.detach(node)
            }
            slot.removeNode(for: engine)
        }

        // Rebuild the chain
        buildChain(for: engine, sourceNode: sourceNode, format: format)

        // Resume if it was running
        if wasRunning {
            try? engine.start()
        }
    }

    private func _teardownAndRebuildAsync(engine: AVAudioEngine, completion: @escaping () -> Void) {
        // Find source BEFORE disconnecting anything
        guard let (sourceNode, format) = findSourceNode(in: engine) else {
            completion()
            return
        }

        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }

        // Disconnect and detach all our effect nodes
        let mixer = engine.mainMixerNode
        engine.disconnectNodeInput(mixer)

        lock.lock()
        let currentSlots = slots
        lock.unlock()

        for slot in currentSlots.compactMap({ $0 }) {
            if let node = slot.node(for: engine) {
                engine.disconnectNodeInput(node)
                engine.disconnectNodeOutput(node)
                engine.detach(node)
            }
            slot.removeNode(for: engine)
        }

        // Connect source directly to mixer as a temporary passthrough while AU loads
        engine.connect(sourceNode, to: mixer, format: format)
        if wasRunning {
            try? engine.start()
        }

        // Rebuild chain async — when done, splice in the full chain
        buildChainAsync(for: engine, sourceNode: sourceNode, format: format) { [weak self] entryNode in
            // The buildChainAsync already wired everything; engine continues playing
            if entryNode != nil, let self = self {
                // Chain was rebuilt successfully with AU nodes
            }
            completion()
        }
    }
}
