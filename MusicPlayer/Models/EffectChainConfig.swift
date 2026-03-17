import Foundation
import AudioToolbox

// MARK: - EffectChainConfig

struct EffectChainConfig: Codable {

    static let slotCount = 8

    // MARK: - SlotConfig

    struct SlotConfig: Codable {
        var type: EffectSlotType
        var isBypassed: Bool

        // AU Plugin fields (nil for built-in slots)
        var auComponentType: UInt32?
        var auComponentSubType: UInt32?
        var auComponentManufacturer: UInt32?
        var auComponentName: String?
        var auComponentManufacturerName: String?
        var auStateFileName: String?
    }

    // MARK: - Properties

    var slots: [SlotConfig?]

    // MARK: - Defaults

    static var defaultConfig: EffectChainConfig {
        var slots: [SlotConfig?] = [
            SlotConfig(type: .eq, isBypassed: false),
            SlotConfig(type: .reverb, isBypassed: false),
            SlotConfig(type: .delay, isBypassed: false),
            SlotConfig(type: .timePitch, isBypassed: false),
            nil,
            nil,
            nil,
            nil
        ]
        // Ensure exactly slotCount entries
        while slots.count < slotCount { slots.append(nil) }
        return EffectChainConfig(slots: Array(slots.prefix(slotCount)))
    }

    // MARK: - Directories

    static var configDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OrangeMusicPlayer/EffectChains", isDirectory: true)
    }

    static var pluginPresetsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OrangeMusicPlayer/PluginPresets", isDirectory: true)
    }

    // MARK: - Persistence

    func save(name: String = "Default") {
        let dir = EffectChainConfig.configDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent("\(name).json")
            let data = try JSONEncoder().encode(self)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[EffectChainConfig] Failed to save config '\(name)': \(error)")
        }
    }

    static func load(name: String = "Default") -> EffectChainConfig {
        let fileURL = configDirectory.appendingPathComponent("\(name).json")
        do {
            let data = try Data(contentsOf: fileURL)
            var config = try JSONDecoder().decode(EffectChainConfig.self, from: data)
            // Pad or trim to exactly slotCount entries
            while config.slots.count < slotCount { config.slots.append(nil) }
            if config.slots.count > slotCount { config.slots = Array(config.slots.prefix(slotCount)) }
            return config
        } catch {
            return defaultConfig
        }
    }
}
