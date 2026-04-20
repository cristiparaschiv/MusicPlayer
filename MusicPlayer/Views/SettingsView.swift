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
    @State private var replayGainMode: ReplayGainMode = .off

    // Cache management
    @State private var showClearCacheAlert: Bool = false
    @State private var cacheSize: String = "Calculating..."
    @State private var isClearingCache: Bool = false

    // Last.fm
    @ObservedObject private var lastFM = LastFMManager.shared
    @State private var lastFMUsername: String = ""
    @State private var lastFMPassword: String = ""
    @State private var lastFMError: String?
    @State private var isConnectingLastFM: Bool = false
    @State private var showVerifySheet: Bool = false
    @State private var showRemoteControl: Bool = false
    @State private var showRestoreBackup: Bool = false
    @State private var iCloudBackups: [BackupInfo] = []
    @State private var showRestoreConfirm: Bool = false
    @State private var selectedBackup: BackupInfo?
    @State private var iCloudBackupStatus: String?

    @ObservedObject private var audioOutputManager = AudioOutputManager.shared
    @ObservedObject private var scanner = MediaScannerManager.shared

    @Environment(\.dismiss)
    var dismiss
    
    enum SettingsTab: Hashable {
        case general
        case playback
        case library
        case about
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTabView
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            PlaybackTabView
                .tabItem { Label("Playback", systemImage: "play.circle") }
                .tag(SettingsTab.playback)

            LibraryTabView
                .tabItem { Label("Library", systemImage: "music.note.house") }
                .tag(SettingsTab.library)

            AboutTabView
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 550, idealWidth: 600, maxWidth: 800,
               minHeight: 580, idealHeight: 650, maxHeight: 900)
        .onAppear {
            loadData()
            loadPlaybackSettings()
            calculateCacheSize()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryPathsChanged)) { _ in
            loadData()
        }
    }
    
    @AppStorage("appAppearance") private var appAppearance: String = "system"

    private var GeneralTabView: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            // Appearance Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .font(.headline)
                    .padding(.bottom, 4)

                HStack {
                    Text("Theme:")
                        .font(.subheadline)

                    Spacer()

                    Picker("", selection: $appAppearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                Text("Override the system appearance for this app only")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

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
                            HStack(spacing: 4) {
                                if device.isAirPlay {
                                    Image(systemName: "airplayaudio")
                                }
                                Text(device.displayName)
                            }.tag(device as AudioDevice?)
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

                if audioOutputManager.currentSampleRate > 0 {
                    HStack {
                        Text("Current Sample Rate:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(AudioOutputManager.formatSampleRate(audioOutputManager.currentSampleRate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text("Select the audio output device for playback. AirPlay devices appear automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                // Sample Rate Switching
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Auto Sample Rate Switching", isOn: $audioOutputManager.isSampleRateSwitchingEnabled)
                        .toggleStyle(.switch)

                    Text("Automatically switch the output device sample rate to match the playing track for bit-perfect playback")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Hog Mode (Exclusive Access)
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Exclusive Mode (Hog Mode)", isOn: Binding(
                        get: { audioOutputManager.isHogModeEnabled },
                        set: { _ in audioOutputManager.toggleHogMode() }
                    ))
                    .toggleStyle(.switch)

                    Text("Take exclusive access to the output device, preventing other apps from using it. Ensures uninterrupted, bit-perfect playback.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Storage Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Storage")
                    .font(.headline)
                    .padding(.bottom, 4)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cache Size:")
                            .font(.subheadline)

                        Text("Artwork and lyrics cache")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(cacheSize)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button(action: { showClearCacheAlert = true }) {
                        if isClearingCache {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 80)
                        } else {
                            Text("Clear Cache")
                                .frame(width: 80)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isClearingCache)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .alert("Clear Cache", isPresented: $showClearCacheAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    clearCache()
                }
            } message: {
                Text("This will delete all cached artwork and lyrics. They will be re-downloaded when needed.")
            }

        }
        .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Playback Tab

    private var PlaybackTabView: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
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

                // ReplayGain
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ReplayGain:")
                            .font(.subheadline)

                        Spacer()

                        Picker("", selection: $replayGainMode) {
                            ForEach(ReplayGainMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        .onChange(of: replayGainMode) { _, newValue in
                            PlayerManager.shared.setReplayGainMode(newValue)
                        }
                    }

                    Text("Normalize volume levels using ReplayGain tags embedded in your audio files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Last.fm Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Last.fm Scrobbling")
                    .font(.headline)
                    .padding(.bottom, 4)

                if lastFM.isAuthenticated {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connected as \(lastFM.username)")
                            .font(.subheadline)
                        Spacer()
                        Button("Disconnect") {
                            lastFM.logout()
                        }
                        .buttonStyle(.bordered)
                    }

                    Toggle("Enable Scrobbling", isOn: Binding(
                        get: { lastFM.scrobblingEnabled },
                        set: { lastFM.scrobblingEnabled = $0 }
                    ))
                    .toggleStyle(.switch)

                    Text("Tracks are scrobbled after 50% played or 4 minutes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Username", text: $lastFMUsername)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Password", text: $lastFMPassword)
                            .textFieldStyle(.roundedBorder)

                        if let error = lastFMError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Button(action: connectLastFM) {
                            if isConnectingLastFM {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Connect")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(lastFMUsername.isEmpty || lastFMPassword.isEmpty || isConnectingLastFM)
                    }

                    Text("Your password is sent directly to Last.fm and is not stored")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Remote Control Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Remote Control")
                    .font(.headline)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Control playback from any device on your network")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Configure...") {
                        showRemoteControl = true
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showRemoteControl) {
            RemoteControlSettingsView()
        }
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
                            let status = scanner.pathStatuses.first(where: { $0.path == path })
                            HStack(spacing: 12) {
                                // Icon: network, unavailable, or local
                                Image(systemName: status?.isNetworkVolume == true ? "network" :
                                      status?.isAvailable == false ? "exclamationmark.triangle.fill" : Icons.folderFill)
                                    .font(.system(size: 16))
                                    .foregroundColor(status?.isAvailable == false ? .red :
                                                     status?.isNetworkVolume == true ? .blue : .accentColor)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(URL(fileURLWithPath: path).lastPathComponent)
                                            .font(.system(size: 13, weight: .medium))

                                        if status?.isNetworkVolume == true {
                                            Text("Network")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.blue.opacity(0.15))
                                                .foregroundColor(.blue)
                                                .cornerRadius(3)
                                        }
                                    }

                                    Text(path)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)

                                    // Scan status line
                                    if let state = status?.scanState {
                                        switch state {
                                        case .scanning(let processed, let total):
                                            HStack(spacing: 4) {
                                                ProgressView()
                                                    .controlSize(.mini)
                                                Text("Scanning: \(processed)/\(total) files")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.orange)
                                            }
                                        case .complete(let count):
                                            Text("\(count) files found")
                                                .font(.system(size: 10))
                                                .foregroundColor(.green)
                                        case .unavailable:
                                            Text("Unavailable — volume not mounted")
                                                .font(.system(size: 10))
                                                .foregroundColor(.red)
                                        case .idle:
                                            EmptyView()
                                        }
                                    }
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

            VStack(spacing: 8) {
                // Row 1: Folder management
                HStack(spacing: 12) {
                    Button(action: removeSelectedPaths) {
                        Label("Remove Selected", systemImage: Icons.minusCircleFill)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedPaths.isEmpty)

                    Button(action: updateFolderAccess) {
                        Label("Update Folder Access", systemImage: "lock.open")
                    }
                    .buttonStyle(.bordered)
                    .disabled(libraryPaths.isEmpty)
                    .help("Re-authorize folders to enable metadata editing")

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

                    Button(action: { showVerifySheet = true }) {
                        Label("Verify Library", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.bordered)
                    .disabled(libraryPaths.isEmpty)
                }

                // Row 2: iCloud backup
                if iCloudBackupManager.shared.isAvailable {
                    HStack(spacing: 12) {
                        Spacer()

                        Button(action: {
                            iCloudBackupManager.shared.backupAfterScan()
                            iCloudBackupStatus = "Backing up..."
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                iCloudBackupStatus = nil
                            }
                        }) {
                            Label(iCloudBackupStatus ?? "Backup to iCloud", systemImage: "icloud.and.arrow.up")
                        }
                        .buttonStyle(.bordered)

                        Button(action: {
                            iCloudBackups = iCloudBackupManager.shared.listBackups()
                            showRestoreBackup = true
                        }) {
                            Label("Restore from iCloud", systemImage: "icloud.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showVerifySheet) {
            LibraryVerifierView()
        }
        .sheet(isPresented: $showRestoreBackup) {
            iCloudBackupSheet
        }
    }

    private var iCloudBackupSheet: some View {
        VStack(spacing: 16) {
            Text("iCloud Backups")
                .font(.headline)

            if iCloudBackups.isEmpty {
                Text("No backups found in iCloud.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(iCloudBackups) { backup in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(backup.formattedDate)
                                .font(.body)
                            Text(backup.formattedSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") {
                            selectedBackup = backup
                            showRestoreConfirm = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(minHeight: 150)
            }

            HStack {
                Button("Cancel") {
                    showRestoreBackup = false
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 400)
        .alert("Restore Backup?", isPresented: $showRestoreConfirm) {
            Button("Restore", role: .destructive) {
                if let backup = selectedBackup {
                    let success = iCloudBackupManager.shared.restore(from: backup)
                    showRestoreBackup = false
                    if success {
                        // Show restart prompt
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.messageText = "Backup Restored"
                            alert.informativeText = "The database has been restored. Please restart the app for changes to take effect."
                            alert.alertStyle = .informational
                            alert.addButton(withTitle: "Restart Now")
                            alert.addButton(withTitle: "Later")
                            if alert.runModal() == .alertFirstButtonReturn {
                                NSApplication.shared.terminate(nil)
                            }
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace your current library database with the backup. This cannot be undone.")
        }
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
                    Text("Created by Cristi Paraschiv")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("© 2026 Orange Music Player. All rights reserved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                // Actions — updates handled by the App Store

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

    // MARK: - Actions

    private func loadData() {
        libraryPaths = MediaScannerManager.shared.getLibraryPaths()
        scanner.refreshPathStatuses()
    }

    private func loadPlaybackSettings() {
        isCrossfadeEnabled = PlayerManager.shared.isCrossfadeEnabled
        crossfadeDuration = PlayerManager.shared.crossfadeDuration
        isGaplessEnabled = PlayerManager.shared.isGaplessEnabled
        replayGainMode = PlayerManager.shared.replayGainMode
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

    private func updateFolderAccess() {
        SecurityBookmarkManager.shared.migrateToReadWrite { _ in }
    }

    // MARK: - Cache Management

    private func calculateCacheSize() {
        DispatchQueue.global(qos: .utility).async {
            let fileManager = FileManager.default
            var totalSize: Int64 = 0

            // Calculate artwork cache size
            let artworkCacheDir = fileManager.cacheDirectory(for: Constants.artworkCacheDirectory)
            totalSize += directorySize(at: artworkCacheDir)

            // Calculate lyrics cache size
            let lyricsCacheDir = fileManager.cacheDirectory(for: Constants.lyricsCacheDirectory)
            totalSize += directorySize(at: lyricsCacheDir)

            let formattedSize = formatBytes(totalSize)

            DispatchQueue.main.async {
                cacheSize = formattedSize
            }
        }
    }

    private func directorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        var size: Int64 = 0

        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                size += Int64(resourceValues.fileSize ?? 0)
            } catch {
                continue
            }
        }

        return size
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func connectLastFM() {
        isConnectingLastFM = true
        lastFMError = nil
        lastFM.authenticate(username: lastFMUsername, password: lastFMPassword) { result in
            isConnectingLastFM = false
            switch result {
            case .success:
                lastFMUsername = ""
                lastFMPassword = ""
            case .failure(let error):
                lastFMError = error.localizedDescription
            }
        }
    }

    private func clearCache() {
        isClearingCache = true

        DispatchQueue.global(qos: .userInitiated).async {
            // Clear artwork cache
            ArtworkManager.shared.clearAllCaches()

            // Clear lyrics cache
            LyricsManager.shared.clearAllCaches()

            DispatchQueue.main.async {
                isClearingCache = false
                // Recalculate cache size
                calculateCacheSize()
            }
        }
    }
}

#Preview {
    SettingsView()
}
