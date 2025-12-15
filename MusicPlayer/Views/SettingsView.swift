import SwiftUI
import AppKit
import Foundation

struct SettingsView: View {

    @State private var selectedTab: SettingsTab = .general
    @State private var libraryPaths: [String] = []
    @State private var selectedPaths: Set<String> = []
    @State private var isScanning: Bool = false

    // Local state for playback settings to ensure proper SwiftUI updates
    @State private var isCrossfadeEnabled: Bool = false
    @State private var crossfadeDuration: Double = 3.0
    @State private var isGaplessEnabled: Bool = false

    @ObservedObject private var audioOutputManager = AudioOutputManager.shared

    @Environment(\.dismiss)
    var dismiss
    
    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case library = "Library"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return Icons.settings
            case .library: return Icons.customMusicNoteRectangleStack
            case .about: return Icons.infoCircle
            }
        }

        var selectedIcon: String {
            switch self {
            case .general: return Icons.settings
            case .library: return Icons.customMusicNoteRectangleStack
            case .about: return Icons.infoCircleFill
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: Icons.xmarkCircleFill)
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .help("Dismiss")
                    .buttonStyle(.plain)
                    .focusable(false)
                    
                    Spacer()
                }
                
                TabbedButtons(
                    items: SettingsTab.allCases,
                    selection: $selectedTab,
                    style: tabbedButtonStyle,
                    animation: .transform
                )
                .focusable(false)
            }
            .padding(10)

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    GeneralTabView
                case .library:
                    LibraryTabView
                case .about:
                    AboutTabView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 500, idealWidth: 600, maxWidth: 800,
               minHeight: 500, idealHeight: 620, maxHeight: 900)
        .onAppear {
            loadData()
            loadPlaybackSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryPathsChanged)) { _ in
            loadData()
        }
    }
    
    private var GeneralTabView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Audio Output Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Audio Output")
                    .font(.headline)
                    .padding(.bottom, 4)

                HStack {
                    Text("Output Device:")
                        .font(.subheadline)

                    Spacer()

                    Picker("", selection: Binding(
                        get: { audioOutputManager.currentDevice },
                        set: { newDevice in
                            if let device = newDevice {
                                _ = audioOutputManager.setOutputDevice(device)
                            }
                        }
                    )) {
                        ForEach(audioOutputManager.availableDevices) { device in
                            Text(device.name).tag(device as AudioDevice?)
                        }
                    }
                    .frame(width: 300)

                    Button(action: {
                        audioOutputManager.refreshDevices()
                    }) {
                        Image(systemName: Icons.arrowClockwise)
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh audio devices")
                }

                Text("Select the audio output device for playback")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Playback Settings Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Playback Settings")
                    .font(.headline)
                    .padding(.bottom, 4)

                // Crossfade Toggle
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Crossfade", isOn: $isCrossfadeEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: isCrossfadeEnabled) { _, newValue in
                            PlayerManager.shared.setCrossfadeEnabled(newValue)
                        }

                    Text("Smoothly fade between tracks during transitions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Crossfade Duration Slider
                if isCrossfadeEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Crossfade Duration:")
                                .font(.subheadline)

                            Spacer()

                            Text("\(Int(crossfadeDuration)) seconds")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Slider(
                            value: $crossfadeDuration,
                            in: 1...10,
                            step: 1
                        )
                        .onChange(of: crossfadeDuration) { _, newValue in
                            PlayerManager.shared.setCrossfadeDuration(newValue)
                        }

                        Text("How long the crossfade transition should last")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)
                }

                // Gapless Playback Toggle
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Gapless Playback", isOn: $isGaplessEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: isGaplessEnabled) { _, newValue in
                            PlayerManager.shared.setGaplessEnabled(newValue)
                        }

                    Text("Eliminate silence between tracks for seamless playback")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var LibraryTabView: some View {
        VStack(spacing: 16) {
            // Header with action buttons
            HStack {
                Text("Music Library Folders")
                    .font(.headline)

                Spacer()

                Button(action: addFolder) {
                    Label("Add Folder", systemImage: Icons.plusCircle)
                }
                .buttonStyle(.bordered)
            }
            .padding()

            // Library paths list
            VStack(alignment: .leading, spacing: 8) {
                if libraryPaths.isEmpty {
                    Text("No library folders added yet")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else {
                    List(selection: $selectedPaths) {
                        ForEach(libraryPaths, id: \.self) { path in
                            HStack(spacing: 12) {
                                Image(systemName: Icons.folderFill)
                                    .font(.system(size: 16))
                                    .foregroundColor(.accentColor)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .font(.system(size: 13, weight: .medium))

                                    Text(path)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .tag(path)
                        }
                    }
                    .listStyle(.inset)
                }
            }

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                Button(action: removeSelectedPaths) {
                    Label("Remove Selected", systemImage: Icons.minusCircleFill)
                }
                .buttonStyle(.bordered)
                .disabled(selectedPaths.isEmpty)

                Spacer()

                Button(action: scanForChanges) {
                    Label("Scan for Changes", systemImage: Icons.arrowClockwise)
                }
                .buttonStyle(.bordered)
                .disabled(libraryPaths.isEmpty || isScanning)

                Button(action: fullRescan) {
                    Label("Full Rescan", systemImage: Icons.arrowClockwise)
                }
                .buttonStyle(.borderedProminent)
                .disabled(libraryPaths.isEmpty || isScanning)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var AboutTabView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App icon and name
                VStack(spacing: 12) {
                    // App icon from application bundle
                    if let appIcon = NSApp.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 128, height: 128)
                            .cornerRadius(24)
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    } else {
                        // Fallback if app icon not available
                        Image(systemName: Icons.musicNoteHouseFill)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100)
                            .foregroundColor(.accentColor)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                    }

                    Text("Orange Music Player")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("A modern music player for macOS")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                Divider()

                // Version information
                VStack(alignment: .leading, spacing: 12) {
                    Text("Version Information")
                        .font(.headline)
                        .padding(.bottom, 4)

                    HStack {
                        Text("Version:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(appVersion)
                            .font(.subheadline)
                    }

                    HStack {
                        Text("Build:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(buildNumber)
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                // Credits
                VStack(alignment: .leading, spacing: 12) {
                    Text("Credits & Acknowledgments")
                        .font(.headline)
                        .padding(.bottom, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Built with:")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("• SFBAudioEngine - High-quality audio playback")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("• SwiftUI - Modern user interface framework")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("• SQLite - Efficient database management")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                // Copyright
                VStack(spacing: 8) {
                    Text("© 2024-2025 Orange Music Player")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("All rights reserved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                // Actions
                VStack(spacing: 12) {
                    Button(action: checkForUpdates) {
                        Label("Check for Updates", systemImage: Icons.arrowClockwise)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    // Links section - uncomment and update URLs when ready
                    /*
                    HStack(spacing: 12) {
                        Button(action: openGitHub) {
                            Label("GitHub", systemImage: "arrow.up.forward.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(action: openWebsite) {
                            Label("Website", systemImage: "arrow.up.forward.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    */
                }

                Spacer()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func checkForUpdates() {
        // Placeholder for update checking functionality
        let alert = NSAlert()
        alert.messageText = "Check for Updates"
        alert.informativeText = "You are using the latest version of Orange Music Player."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func openGitHub() {
        if let url = URL(string: "https://github.com") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openWebsite() {
        if let url = URL(string: "https://example.com") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private var tabbedButtonStyle: TabbedButtonStyle {
        if #available(macOS 26.0, *) {
            return .moderncompact
        } else {
            return .compact
        }
    }
    
    // MARK: - Actions

    private func loadData() {
        libraryPaths = MediaScannerManager.shared.getLibraryPaths()
    }

    private func loadPlaybackSettings() {
        isCrossfadeEnabled = PlayerManager.shared.isCrossfadeEnabled
        crossfadeDuration = PlayerManager.shared.crossfadeDuration
        isGaplessEnabled = PlayerManager.shared.isGaplessEnabled
    }

    private func addFolder() {
        MediaScannerManager.shared.addFolder()
        // Data will be reloaded automatically via notification observer
    }

    private func removeSelectedPaths() {
        for path in selectedPaths {
            MediaScannerManager.shared.removeLibraryPath(path)
        }
        selectedPaths.removeAll()
        // Data will be reloaded automatically via notification observer
    }

    private func scanForChanges() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            MediaScannerManager.shared.scanForChanges()
            DispatchQueue.main.async {
                isScanning = false
            }
        }
    }

    private func fullRescan() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            MediaScannerManager.shared.fullRescan()
            DispatchQueue.main.async {
                isScanning = false
            }
        }
    }
}

#Preview {
    SettingsView()
}
