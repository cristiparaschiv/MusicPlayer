import SwiftUI

struct PlaylistView: View {
    let playlist: Playlist?
    let isFavorites: Bool

    @State private var tracks: [Track] = []
    @State private var showingDeleteAlert = false
    @State private var showingClearAlert = false
    @State private var showingSmartPlaylistEditor = false
    @State private var trackToEdit: Track?
    @State private var importMessage: String?

    @Environment(\.dismiss) private var dismiss

    private let trackDAO = TrackDAO()
    private let playlistDAO = PlaylistDAO()

    init(playlist: Playlist) {
        self.playlist = playlist
        self.isFavorites = false
    }

    init(favorites: Bool) {
        self.playlist = nil
        self.isFavorites = true
    }

    private var displayName: String {
        isFavorites ? "Favorites" : (playlist?.name ?? "Playlist")
    }

    private var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    if isFavorites {
                        Color.pink.opacity(0.3)
                        Image(systemName: Icons.starFill)
                            .font(.system(size: 40))
                            .foregroundColor(.pink)
                    } else {
                        Color.blue.opacity(0.3)
                        Image(systemName: Icons.musicNoteList)
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                    }
                }
                .frame(width: 100, height: 100)
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 8) {
                    Text(displayName)
                        .font(.largeTitle)
                        .bold()

                    HStack(spacing: 8) {
                        Text("\(tracks.count) \(tracks.count == 1 ? "song" : "songs")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if !tracks.isEmpty {
                            Text("\u{2022}")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(totalDuration.formattedDuration)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        if !tracks.isEmpty {
                            Button(action: playAll) {
                                HStack(spacing: 4) {
                                    Image(systemName: Icons.playFill)
                                    Text("Play")
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button(action: { showingClearAlert = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: Icons.trash)
                                    Text("Clear")
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        if !isFavorites && playlist?.isSmartPlaylist == true {
                            Button(action: { showingSmartPlaylistEditor = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "slider.horizontal.3")
                                    Text("Edit Rules")
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        if !isFavorites && !tracks.isEmpty {
                            Button(action: {
                                PlaylistManager.shared.exportPlaylist(name: displayName, tracks: tracks)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export")
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        if !isFavorites {
                            Button(action: { showingDeleteAlert = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: Icons.trash)
                                    Text("Delete Playlist")
                                }
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .background(.regularMaterial)

            Divider()

            // Content
            if tracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: isFavorites ? Icons.starFill : Icons.musicNoteList)
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text(isFavorites ? "No favorite songs yet" : "This playlist is empty")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text(isFavorites ? "Mark songs as favorites to see them here" : (playlist?.isSmartPlaylist == true ? "No songs match the current smart playlist criteria" : "Add songs to this playlist from the Songs view or album views"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackTableView(
                    tracks: tracks,
                    config: TrackTableConfig(
                        showRemoveFromPlaylist: true,
                        removeFromPlaylistLabel: "Remove from \(displayName)",
                        onRemoveFromPlaylist: { trackIDs in
                            for id in trackIDs {
                                removeFromPlaylist(trackId: id)
                            }
                        },
                        onEditTrack: { trackToEdit = $0 },
                        allowReorder: !isFavorites && playlist?.isSmartPlaylist != true,
                        onReorder: { newOrder in
                            guard let playlistId = playlist?.id else { return }
                            playlistDAO.reorderTracks(playlistId: playlistId, trackIds: newOrder)
                        }
                    ),
                    onPlayTrack: { track, allTracks in
                        if let index = allTracks.firstIndex(where: { $0.id == track.id }) {
                            QueueManager.shared.setQueue(allTracks, startIndex: index)
                            PlayerManager.shared.play(track: track)
                        }
                    }
                )
            }
        }
        .alert("Delete Playlist", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deletePlaylist()
            }
        } message: {
            Text("Are you sure you want to delete \"\(displayName)\"? This action cannot be undone.")
        }
        .alert("Clear Playlist", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearPlaylist()
            }
        } message: {
            Text("Are you sure you want to remove all songs from \"\(displayName)\"?")
        }
        .sheet(item: $trackToEdit) { track in
            TrackEditorView(track: track)
        }
        .sheet(isPresented: $showingSmartPlaylistEditor) {
            if let playlist = playlist {
                SmartPlaylistEditorView(isPresented: $showingSmartPlaylistEditor, existingPlaylist: playlist) { newName, newCriteria in
                    saveSmartPlaylist(name: newName, criteria: newCriteria)
                }
            }
        }
        .onAppear {
            loadTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
            loadTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.trackFavoriteChanged)) { _ in
            if isFavorites {
                loadTracks()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.playlistContentChanged)) { notification in
            if let changedPlaylistId = notification.userInfo?["playlistId"] as? Int64,
               changedPlaylistId == playlist?.id {
                loadTracks()
            }
        }
    }

    // MARK: - Actions

    private func loadTracks() {
        if isFavorites {
            tracks = trackDAO.getFavorites()
        } else if let playlist = playlist {
            if playlist.isSmartPlaylist,
               let json = playlist.smartCriteria,
               let data = json.data(using: .utf8),
               let criteria = try? JSONDecoder().decode(SmartPlaylistCriteria.self, from: data) {
                tracks = playlistDAO.getTracksForSmartPlaylist(criteria: criteria)
            } else {
                tracks = playlistDAO.getTracksForPlaylist(playlistId: playlist.id)
            }
        }
    }

    private func playAll() {
        guard !tracks.isEmpty else { return }
        QueueManager.shared.setQueue(tracks, startIndex: 0)
        PlayerManager.shared.play(track: tracks[0])
    }

    private func clearPlaylist() {
        if isFavorites {
            for track in tracks {
                trackDAO.updateFavorite(trackId: track.id, isFavorite: false)
            }
            NotificationCenter.default.post(name: Constants.Notifications.trackFavoriteChanged, object: nil)
        } else if let playlist = playlist {
            for track in tracks {
                playlistDAO.removeTrack(playlistId: playlist.id, trackId: track.id)
            }
            NotificationCenter.default.post(
                name: Constants.Notifications.playlistContentChanged,
                object: nil,
                userInfo: ["playlistId": playlist.id]
            )
        }
        loadTracks()
    }

    private func deletePlaylist() {
        guard let playlist = playlist else { return }
        playlistDAO.delete(playlistId: playlist.id)
        NotificationCenter.default.post(name: Constants.Notifications.playlistsChanged, object: nil)
        dismiss()
    }

    private func saveSmartPlaylist(name: String, criteria: SmartPlaylistCriteria) {
        guard var updatedPlaylist = playlist else { return }
        let jsonData = try? JSONEncoder().encode(criteria)
        let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) }
        let trackCount = playlistDAO.getSmartPlaylistTrackCount(criteria: criteria)

        let newPlaylist = Playlist(
            id: updatedPlaylist.id,
            name: name,
            dateCreated: updatedPlaylist.dateCreated,
            dateModified: Date(),
            isSmartPlaylist: true,
            smartCriteria: jsonString,
            trackCount: trackCount
        )
        playlistDAO.update(playlist: newPlaylist)
        NotificationCenter.default.post(name: Constants.Notifications.playlistsChanged, object: nil)
        loadTracks()
    }

    private func removeFromPlaylist(trackId: Int64) {
        if isFavorites {
            trackDAO.updateFavorite(trackId: trackId, isFavorite: false)
            NotificationCenter.default.post(name: Constants.Notifications.trackFavoriteChanged, object: nil)
        } else if let playlist = playlist {
            playlistDAO.removeTrack(playlistId: playlist.id, trackId: trackId)
            NotificationCenter.default.post(
                name: Constants.Notifications.playlistContentChanged,
                object: nil,
                userInfo: ["playlistId": playlist.id]
            )
        }
        loadTracks()
    }
}
