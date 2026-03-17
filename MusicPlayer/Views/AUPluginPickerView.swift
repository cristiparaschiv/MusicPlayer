import SwiftUI

struct AUPluginPickerView: View {
    let slotIndex: Int
    let onSelectBuiltIn: (EffectSlotType) -> Void
    let onSelectAU: (AUPluginInfo) -> Void

    @ObservedObject private var pluginManager = AUPluginManager.shared
    @State private var selectedTab = 0
    @State private var searchText = ""

    private let builtIns: [(name: String, icon: String, type: EffectSlotType)] = [
        ("Equalizer",   "slider.vertical.3",  .eq),
        ("Reverb",      "waveform.path",       .reverb),
        ("Delay",       "repeat",              .delay),
        ("Pitch / Speed", "metronome",         .timePitch),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Built-in").tag(0)
                Text("Audio Units").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(10)

            Divider()

            if selectedTab == 0 {
                builtInList
            } else {
                auList
            }
        }
        .frame(width: 280, height: 300)
    }

    // MARK: - Built-in list

    private var builtInList: some View {
        List(builtIns, id: \.type) { item in
            Button(action: { onSelectBuiltIn(item.type) }) {
                Label(item.name, systemImage: item.icon)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
        }
        .listStyle(.plain)
    }

    // MARK: - AU plugin list

    private var auList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if pluginManager.availablePlugins.isEmpty {
                VStack {
                    Spacer()
                    Text("No Audio Unit plugins found")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                }
            } else {
                let manufacturers = filteredManufacturers
                if manufacturers.isEmpty {
                    VStack {
                        Spacer()
                        Text("No results")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(manufacturers, id: \.self) { mfr in
                            Section(mfr) {
                                ForEach(filteredPlugins(for: mfr)) { plugin in
                                    Button(action: { onSelectAU(plugin) }) {
                                        HStack(spacing: 8) {
                                            if let icon = plugin.icon {
                                                Image(nsImage: icon)
                                                    .resizable()
                                                    .frame(width: 16, height: 16)
                                            } else {
                                                Image(systemName: "puzzlepiece")
                                                    .frame(width: 16, height: 16)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text(plugin.name)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, 1)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    // MARK: - Filtering

    private var filteredManufacturers: [String] {
        pluginManager.pluginsByManufacturer.keys
            .filter { mfr in
                searchText.isEmpty || !filteredPlugins(for: mfr).isEmpty
            }
            .sorted()
    }

    private func filteredPlugins(for manufacturer: String) -> [AUPluginInfo] {
        let plugins = pluginManager.pluginsByManufacturer[manufacturer] ?? []
        guard !searchText.isEmpty else { return plugins }
        return plugins.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.manufacturerName.localizedCaseInsensitiveContains(searchText)
        }
    }
}
