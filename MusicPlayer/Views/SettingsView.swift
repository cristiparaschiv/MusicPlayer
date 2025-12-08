import SwiftUI
import AppKit
import Foundation

struct SettingsView: View {

    @State private var selectedTab: SettingsTab = .general
    @State private var libraryPaths: [String] = []
    @State private var selectedPaths: Set<String> = []
    @State private var isScanning: Bool = false

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
        .frame(width: 600, height: 620)
        .onAppear {
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryPathsChanged)) { _ in
            loadData()
        }
    }
    
    private var GeneralTabView: some View {
        EmptyView()
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
        EmptyView()
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
