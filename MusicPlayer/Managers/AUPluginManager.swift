import AVFoundation
import AudioToolbox
import AppKit
import Combine

// MARK: - AUPluginInfo

struct AUPluginInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let manufacturerName: String
    let componentDescription: AudioComponentDescription
    let icon: NSImage?

    static func == (lhs: AUPluginInfo, rhs: AUPluginInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - AUPluginManager

final class AUPluginManager: ObservableObject {
    static let shared = AUPluginManager()

    @Published var availablePlugins: [AUPluginInfo] = []
    @Published var pluginsByManufacturer: [String: [AUPluginInfo]] = [:]

    private var cancellables = Set<AnyCancellable>()

    private init() {
        scan()
        NotificationCenter.default.publisher(for: .AVAudioUnitComponentTagsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scan() }
            .store(in: &cancellables)
    }

    func scan() {
        let manager = AVAudioUnitComponentManager.shared()

        var desc = AudioComponentDescription()
        desc.componentType = kAudioUnitType_Effect
        desc.componentSubType = 0
        desc.componentManufacturer = 0
        desc.componentFlags = 0
        desc.componentFlagsMask = 0

        let components = manager.components(matching: desc)

        let plugins = components.map { component -> AUPluginInfo in
            let acd = component.audioComponentDescription
            let idString = "\(acd.componentType)-\(acd.componentSubType)-\(acd.componentManufacturer)"
            return AUPluginInfo(
                id: idString,
                name: component.name,
                manufacturerName: component.manufacturerName,
                componentDescription: acd,
                icon: component.icon
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let grouped = Dictionary(grouping: plugins, by: \.manufacturerName)

        DispatchQueue.main.async {
            self.availablePlugins = plugins
            self.pluginsByManufacturer = grouped
        }
    }
}
