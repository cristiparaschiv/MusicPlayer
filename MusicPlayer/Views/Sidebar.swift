import SwiftUI
import UniformTypeIdentifiers

struct Sidebar: View {
    @Binding var selection: SidebarItem?
    @State private var playlists: [Playlist] = []
    @State private var showingNewPlaylistAlert = false
    @State private var showingSmartPlaylistEditor = false
    @State private var newPlaylistName = ""
    @State private var hoveredPlaylistId: Int64? = nil
    @State private var playlistToDelete: Playlist? = nil
    @State private var showingDeleteConfirmation = false
    @State private var playlistToRename: Playlist? = nil
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var dropTargetPlaylistId: Int64? = nil
    @State private var importMessage: String?
    @State private var availableStations: [RadioStation] = []
    @ObservedObject private var scanner = MediaScannerManager.shared

    private let playlistDAO = PlaylistDAO()

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Library") {
                    NavigationLink(value: SidebarItem.home) {
                        Label("Home", systemImage: "house.fill")
                    }
                    NavigationLink(value: SidebarItem.artists) {
                        Label("Artists", systemImage: "person.2.fill")
                    }
                    NavigationLink(value: SidebarItem.albums) {
                        Label("Albums", systemImage: "opticaldisc.fill")
                    }
                    NavigationLink(value: SidebarItem.songs) {
                        Label("Songs", systemImage: "music.note")
                    }
                    NavigationLink(value: SidebarItem.columnBrowser) {
                        Label("Browser", systemImage: "rectangle.split.3x1")
                    }
                    NavigationLink(value: SidebarItem.folders) {
                        Label("Folders", systemImage: "folder.fill")
                    }
                }

                Section("Discover") {
                    NavigationLink(value: SidebarItem.recentlyAdded) {
                        Label("Recently Added", systemImage: "clock.fill")
                    }
                    NavigationLink(value: SidebarItem.favorites) {
                        Label("Liked Songs", systemImage: "heart.fill")
                    }
                    NavigationLink(value: SidebarItem.stats) {
                        Label("Statistics", systemImage: "chart.bar.fill")
                    }
                }

                Section("Tools") {
                    NavigationLink(value: SidebarItem.scripts) {
                        Label("Scripts", systemImage: "applescript")
                    }
                }

                Section("Playlists") {
                    // User playlists
                    ForEach(playlists, id: \.id) { playlist in
                        NavigationLink(value: SidebarItem.playlist(playlist)) {
                            HStack {
                                Label(playlist.name, systemImage: playlist.isSmartPlaylist ? "gearshape.2" : "music.note.list")

                                Spacer()

                                // Delete button (shows on hover)
                                if hoveredPlaylistId == playlist.id {
                                    Button(action: {
                                        playlistToDelete = playlist
                                        showingDeleteConfirmation = true
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .onDrop(of: [.plainText], isTargeted: Binding(
                                get: { dropTargetPlaylistId == playlist.id },
                                set: { dropTargetPlaylistId = $0 ? playlist.id : nil }
                            )) { providers in
                                handleDrop(providers: providers, playlistId: playlist.id)
                            }
                            .background(dropTargetPlaylistId == playlist.id ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(4)
                        }
                        .onHover { hovering in
                            hoveredPlaylistId = hovering ? playlist.id : nil
                        }
                        .contextMenu {
                            Button("Rename...") {
                                playlistToRename = playlist
                                renameText = playlist.name
                                showingRenameAlert = true
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                playlistToDelete = playlist
                                showingDeleteConfirmation = true
                            }
                        }
                    }
                }

                if !availableStations.isEmpty {
                    Section("Radio") {
                        ForEach(availableStations) { station in
                            NavigationLink(value: SidebarItem.radio(station)) {
                                Label(station.name, systemImage: station.icon)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Spacer()

            // Scan progress indicator
            if scanner.isScanningPublished {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(scanner.scanProgress)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            // Bottom buttons
            HStack(spacing: 0) {
                Menu {
                    Button(action: { showingNewPlaylistAlert = true }) {
                        Label("New Playlist", systemImage: "music.note.list")
                    }
                    Button(action: { showingSmartPlaylistEditor = true }) {
                        Label("New Smart Playlist", systemImage: "gearshape.2")
                    }
                    Divider()
                    Button(action: {
                        PlaylistManager.shared.importPlaylist { message in
                            importMessage = message
                        }
                    }) {
                        Label("Import Playlist", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .padding(10)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("New playlist")

                Spacer()

                SettingsLink {
                    Image(systemName: "gearshape")
                        .padding(10)
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
            .padding(.leading, 6)
            .padding(.bottom, 10)
        }
        .alert("New Playlist", isPresented: $showingNewPlaylistAlert) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
            }
            Button("Create") {
                createPlaylist()
            }
            .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Enter a name for your new playlist")
        }
        .sheet(isPresented: $showingSmartPlaylistEditor) {
            SmartPlaylistEditorView(isPresented: $showingSmartPlaylistEditor) { name, criteria in
                createSmartPlaylist(name: name, criteria: criteria)
            }
        }
        .alert("Import Playlist", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .alert("Rename Playlist", isPresented: $showingRenameAlert) {
            TextField("Playlist name", text: $renameText)
            Button("Cancel", role: .cancel) {
                playlistToRename = nil
                renameText = ""
            }
            Button("Rename") {
                if let playlist = playlistToRename {
                    renamePlaylist(playlist, to: renameText)
                    playlistToRename = nil
                    renameText = ""
                }
            }
            .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Enter a new name for the playlist")
        }
        .alert("Delete Playlist", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                playlistToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let playlist = playlistToDelete {
                    deletePlaylist(playlist)
                    playlistToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(playlistToDelete?.name ?? "")\"? This cannot be undone.")
        }
        .onAppear {
            loadPlaylists()
            loadAvailableStations()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
            loadAvailableStations()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.playlistsChanged)) { _ in
            loadPlaylists()
        }
    }

    private func loadPlaylists() {
        playlists = playlistDAO.getAll()
    }

    private func loadAvailableStations() {
        let dao = TrackDAO()
        availableStations = RadioStation.allStations.filter { station in
            dao.countTracksByGenreKeywords(station.keywords, excludingKeywords: station.excludedKeywords) > 0
        }
    }

    private func createPlaylist() {
        let trimmedName = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let newPlaylist = Playlist(id: 0, name: trimmedName)
        let playlistId = playlistDAO.insert(playlist: newPlaylist)

        // Load the new playlist and select it
        if let createdPlaylist = playlistDAO.getById(id: playlistId) {
            selection = .playlist(createdPlaylist)
        }

        newPlaylistName = ""
        NotificationCenter.default.post(name: Constants.Notifications.playlistsChanged, object: nil)
    }

    private func createSmartPlaylist(name: String, criteria: SmartPlaylistCriteria) {
        let jsonData = try? JSONEncoder().encode(criteria)
        let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) }
        let trackCount = playlistDAO.getSmartPlaylistTrackCount(criteria: criteria)

        let newPlaylist = Playlist(
            id: 0,
            name: name,
            isSmartPlaylist: true,
            smartCriteria: jsonString,
            trackCount: trackCount
        )
        let playlistId = playlistDAO.insert(playlist: newPlaylist)

        if let createdPlaylist = playlistDAO.getById(id: playlistId) {
            selection = .playlist(createdPlaylist)
        }

        NotificationCenter.default.post(name: Constants.Notifications.playlistsChanged, object: nil)
    }

    private func renamePlaylist(_ playlist: Playlist, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let updated = Playlist(
            id: playlist.id,
            name: trimmed,
            dateCreated: playlist.dateCreated,
            dateModified: Date(),
            isSmartPlaylist: playlist.isSmartPlaylist,
            smartCriteria: playlist.smartCriteria,
            trackCount: playlist.trackCount
        )
        playlistDAO.update(playlist: updated)

        // Update selection if this playlist is selected
        if case .playlist(let selected) = selection, selected.id == playlist.id {
            selection = .playlist(updated)
        }

        NotificationCenter.default.post(name: Constants.Notifications.playlistsChanged, object: nil)
    }

    private func deletePlaylist(_ playlist: Playlist) {
        playlistDAO.delete(playlistId: playlist.id)

        // If the deleted playlist is selected, navigate to artists
        if case .playlist(let selectedPlaylist) = selection, selectedPlaylist.id == playlist.id {
            selection = .artists
        }

        NotificationCenter.default.post(name: Constants.Notifications.playlistsChanged, object: nil)
    }

    private func handleDrop(providers: [NSItemProvider], playlistId: Int64) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { item, _ in
                    guard let str = item as? String,
                          let trackIDs = TrackDragHelper.decode(str) else { return }
                    DispatchQueue.main.async {
                        let dao = PlaylistDAO()
                        for id in trackIDs {
                            dao.addTrack(playlistId: playlistId, trackId: id)
                        }
                        NotificationCenter.default.post(
                            name: Constants.Notifications.playlistContentChanged,
                            object: nil,
                            userInfo: ["playlistId": playlistId]
                        )
                    }
                }
                return true
            }
        }
        return false
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
