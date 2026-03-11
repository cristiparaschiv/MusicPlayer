import SwiftUI

struct FolderNode: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isFolder: Bool
    var children: [FolderNode]?
    var trackId: Int64?
}

struct FolderBrowserView: View {
    @State private var rootNodes: [FolderNode] = []
    @State private var selectedFolder: String?
    @State private var tracks: [Track] = []
    @State private var trackToEdit: Track?
    @State private var isLoading = true

    private let trackDAO = TrackDAO()
    private let db = DatabaseManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Folders")
                    .font(.largeTitle)
                    .bold()
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("\(tracks.count) tracks")
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            HSplitView {
                // Folder tree
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rootNodes) { node in
                            FolderTreeRow(node: node, selectedFolder: $selectedFolder)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minWidth: 250, idealWidth: 300)

                // Track list
                TrackTableView(
                    tracks: tracks,
                    config: TrackTableConfig(onEditTrack: { trackToEdit = $0 }),
                    onPlayTrack: { track, allTracks in
                        if let index = allTracks.firstIndex(where: { $0.id == track.id }) {
                            QueueManager.shared.setQueue(allTracks, startIndex: index)
                            PlayerManager.shared.play(track: track)
                        }
                    }
                )
            }
        }
        .onAppear { buildTree() }
        .onChange(of: selectedFolder) { _, newFolder in
            loadTracksForFolder(newFolder)
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
            buildTree()
        }
        .sheet(item: $trackToEdit) { track in
            TrackEditorView(track: track)
        }
    }

    /// Build folder tree from database paths instead of filesystem traversal
    private func buildTree() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let libraryPaths = MediaScannerManager.shared.getLibraryPaths()

            // Query all distinct directory paths from the database
            let sql = "SELECT DISTINCT file_path FROM tracks ORDER BY file_path"
            let results = db.query(sql: sql, parameters: [])
            let filePaths = results.compactMap { $0["file_path"] as? String }

            // Build a set of all directories that contain tracks
            var dirSet = Set<String>()
            for filePath in filePaths {
                let dir = (filePath as NSString).deletingLastPathComponent
                // Add the directory and all its ancestors up to a library root
                var current = dir
                while !current.isEmpty && current != "/" {
                    if dirSet.contains(current) { break }
                    dirSet.insert(current)
                    current = (current as NSString).deletingLastPathComponent
                }
            }

            // Build tree nodes for each library path
            // Disambiguate root nodes with same name by showing parent folder
            let rootNames = libraryPaths.map { ($0 as NSString).lastPathComponent }
            let nameCounts = Dictionary(rootNames.map { ($0, 1) }, uniquingKeysWith: +)

            var nodes: [FolderNode] = []
            for libraryPath in libraryPaths {
                var node = buildNodeFromDB(path: libraryPath, directories: dirSet)
                let baseName = (libraryPath as NSString).lastPathComponent
                if (nameCounts[baseName] ?? 1) > 1 {
                    let parent = ((libraryPath as NSString).deletingLastPathComponent as NSString).lastPathComponent
                    node = FolderNode(name: "\(baseName) (\(parent))", path: node.path, isFolder: true, children: node.children)
                }
                nodes.append(node)
            }

            let firstPath = libraryPaths.first
            DispatchQueue.main.async {
                rootNodes = nodes
                isLoading = false
                if selectedFolder == nil, let first = firstPath {
                    selectedFolder = first
                    loadTracksForFolder(first)
                }
            }
        }
    }

    /// Recursively build folder nodes using the database-derived directory set
    private func buildNodeFromDB(path: String, directories: Set<String>) -> FolderNode {
        let name = (path as NSString).lastPathComponent

        // Find child directories from our set
        var children: [FolderNode] = []
        for dir in directories {
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == path && dir != path {
                children.append(buildNodeFromDB(path: dir, directories: directories))
            }
        }

        children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return FolderNode(
            name: name,
            path: path,
            isFolder: true,
            children: children.isEmpty ? nil : children
        )
    }

    private func loadTracksForFolder(_ folder: String?) {
        guard let folder = folder else {
            tracks = []
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let escapedPath = folder.replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let sql = "SELECT * FROM tracks WHERE file_path LIKE ? ESCAPE '\\' ORDER BY file_path"
            let results = db.query(sql: sql, parameters: [escapedPath + "/%"])
            let loadedTracks = results.compactMap { trackDAO.trackFromRow($0) }
            DispatchQueue.main.async {
                tracks = loadedTracks
            }
        }
    }
}

// MARK: - Folder Tree Row

struct FolderTreeRow: View {
    let node: FolderNode
    @Binding var selectedFolder: String?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if node.children != nil {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .onTapGesture { isExpanded.toggle() }
                } else {
                    Spacer().frame(width: 12)
                }

                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundColor(.blue)

                Text(node.name)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(selectedFolder == node.path ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedFolder = node.path
                if node.children != nil {
                    isExpanded = true
                }
            }

            if isExpanded, let children = node.children {
                ForEach(children) { child in
                    FolderTreeRow(node: child, selectedFolder: $selectedFolder)
                        .padding(.leading, 16)
                }
            }
        }
    }
}
