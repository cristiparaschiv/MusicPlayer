import SwiftUI

struct Sidebar: View {
    @Binding var selection: SidebarItem?
    @State private var playlists: [Playlist] = []
    @State private var showingNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var hoveredPlaylistId: Int64? = nil

    private let settingsManager = SettingsWindowManager()
    private let playlistDAO = PlaylistDAO()

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    NavigationLink(value: SidebarItem.home) {
                        Label("Home", systemImage: "house.fill")
                    }
                    NavigationLink(value: SidebarItem.albums) {
                        Label("Albums", systemImage: "opticaldisc.fill")
                    }
                    NavigationLink(value: SidebarItem.artists) {
                        Label("Artists", systemImage: "person.2.fill")
                    }
                    NavigationLink(value: SidebarItem.songs) {
                        Label("Songs", systemImage: "music.note")
                    }
                }

                Section("Playlists") {
                    // Favorites (always first)
                    NavigationLink(value: SidebarItem.favorites) {
                        Label("Favorites", systemImage: Icons.starFill)
                    }

                    // User playlists
                    ForEach(playlists, id: \.id) { playlist in
                        NavigationLink(value: SidebarItem.playlist(playlist)) {
                            HStack {
                                Label(playlist.name, systemImage: Icons.musicNoteList)

                                Spacer()

                                // Delete button (shows on hover)
                                if hoveredPlaylistId == playlist.id {
                                    Button(action: {
                                        deletePlaylist(playlist)
                                    }) {
                                        Image(systemName: Icons.xmarkCircleFill)
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .onHover { hovering in
                            hoveredPlaylistId = hovering ? playlist.id : nil
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Spacer()

            // Bottom buttons
            HStack(spacing: 0) {
                Button(action: { showingNewPlaylistAlert = true }) {
                    Label("New Playlist", systemImage: Icons.plusCircle)
                        .padding(10)
                }
                .buttonStyle(.borderless)
                .help("Create new playlist")

                Spacer()

                Button(action: { settingsManager.show() }) {
                    Label("Settings", systemImage: "gearshape")
                        .padding(10)
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
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
        .onAppear {
            loadPlaylists()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.playlistsChanged)) { _ in
            loadPlaylists()
        }
    }

    private func loadPlaylists() {
        playlists = playlistDAO.getAll()
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

    private func deletePlaylist(_ playlist: Playlist) {
        playlistDAO.delete(playlistId: playlist.id)

        // If the deleted playlist is selected, navigate to home
        if case .playlist(let selectedPlaylist) = selection, selectedPlaylist.id == playlist.id {
            selection = .home
        }

        NotificationCenter.default.post(name: Constants.Notifications.playlistsChanged, object: nil)
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
