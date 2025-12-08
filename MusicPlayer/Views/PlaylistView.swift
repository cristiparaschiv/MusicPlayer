import SwiftUI

struct PlaylistView: View {
    let playlist: Playlist?  // nil for Favorites
    let isFavorites: Bool

    @State private var tracks: [Track] = []
    @State private var sortedTracks: [Track] = []
    @State private var selection = Set<Track.ID>()
    @State private var sortOrder: [KeyPathComparator<Track>] = []
    @State private var showingDeleteAlert = false
    @State private var showingClearAlert = false

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
                // Playlist icon/artwork placeholder
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
                            Text("•")
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

            // Table
            if tracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: isFavorites ? Icons.starFill : Icons.musicNoteList)
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text(isFavorites ? "No favorite songs yet" : "This playlist is empty")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text(isFavorites ? "Mark songs as favorites to see them here" : "Add songs to this playlist from the Songs view or album views")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(sortedTracks, selection: $selection, sortOrder: $sortOrder) {
                    trackNumberColumn
                    titleColumn
                    artistColumn
                    albumColumn
                    yearColumn
                    durationColumn
                }
                .contextMenu(forSelectionType: Track.ID.self) { items in
                    if items.isEmpty {
                        // No selection
                    } else if items.count == 1 {
                        singleTrackContextMenu(trackId: items.first!)
                    } else {
                        multipleTracksContextMenu(trackIds: items)
                    }
                }
                .onChange(of: sortOrder) { _, newOrder in
                    applySorting(newOrder)
                }
                .onTapGesture(count: 2) {
                    handleDoubleClick()
                }
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
            tracks = playlistDAO.getTracksForPlaylist(playlistId: playlist.id)
        }
        applySorting(sortOrder)
    }

    private func applySorting(_ order: [KeyPathComparator<Track>]) {
        sortedTracks = tracks.sorted { track1, track2 in
            let artist1 = track1.displayArtist.lowercased()
            let artist2 = track2.displayArtist.lowercased()
            if artist1 != artist2 {
                return artist1 < artist2
            }

            let year1 = track1.year ?? Int.max
            let year2 = track2.year ?? Int.max
            if year1 != year2 {
                return year1 < year2
            }

            let album1 = track1.displayAlbum.lowercased()
            let album2 = track2.displayAlbum.lowercased()
            if album1 != album2 {
                return album1 < album2
            }

            let disc1 = track1.discNumber ?? 0
            let disc2 = track2.discNumber ?? 0
            if disc1 != disc2 {
                return disc1 < disc2
            }

            let trackNum1 = track1.trackNumber ?? Int.max
            let trackNum2 = track2.trackNumber ?? Int.max
            return trackNum1 < trackNum2
        }

        if !order.isEmpty {
            sortedTracks.sort(using: order)
        }
    }

    private func playAll() {
        guard !sortedTracks.isEmpty else { return }
        QueueManager.shared.setQueue(sortedTracks, startIndex: 0)
        PlayerManager.shared.play(track: sortedTracks[0])
    }

    private func clearPlaylist() {
        if isFavorites {
            // Clear all favorites
            for track in tracks {
                trackDAO.updateFavorite(trackId: track.id, isFavorite: false)
            }
            NotificationCenter.default.post(name: Constants.Notifications.trackFavoriteChanged, object: nil)
        } else if let playlist = playlist {
            // Remove all tracks from playlist
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

        // Navigate back to home
        dismiss()
    }

    private func handleDoubleClick() {
        guard let selectedId = selection.first,
              let track = sortedTracks.first(where: { $0.id == selectedId }) else {
            return
        }
        playTrack(track)
    }

    private func playTrack(_ track: Track) {
        if QueueManager.shared.isEmpty {
            if let index = sortedTracks.firstIndex(where: { $0.id == track.id }) {
                let queueTracks = Array(sortedTracks[index...])
                QueueManager.shared.setQueue(queueTracks, startIndex: 0)
                PlayerManager.shared.play(track: track)
            }
        } else {
            QueueManager.shared.setQueue([track], startIndex: 0)
            PlayerManager.shared.play(track: track)
        }
    }

    private func playTracks(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }

        let orderedTracks = sortedTracks.filter { track in
            tracks.contains(where: { $0.id == track.id })
        }

        QueueManager.shared.setQueue(orderedTracks, startIndex: 0)
        PlayerManager.shared.play(track: orderedTracks[0])
    }

    private func showInFinder(track: Track) {
        let url = URL(fileURLWithPath: track.filePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func removeFromPlaylist(trackId: Track.ID) {
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

    // MARK: - Context Menus

    @ViewBuilder
    private func singleTrackContextMenu(trackId: Track.ID) -> some View {
        if let track = sortedTracks.first(where: { $0.id == trackId }) {
            Button("Play Now") {
                playTrack(track)
            }

            Button("Add to Queue") {
                QueueManager.shared.addToQueue([track])
            }

            Button("Play Next") {
                QueueManager.shared.insertNext([track])
            }

            Divider()

            Button("Remove from \(displayName)") {
                removeFromPlaylist(trackId: trackId)
            }

            Divider()

            Button(track.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                PlayerManager.shared.toggleFavorite(track: track)
            }

            Divider()

            AddToPlaylistMenu(tracks: [track])

            Divider()

            Button("Show in Finder") {
                showInFinder(track: track)
            }
        }
    }

    @ViewBuilder
    private func multipleTracksContextMenu(trackIds: Set<Track.ID>) -> some View {
        let selectedTracks = sortedTracks.filter { trackIds.contains($0.id) }

        Button("Play Now") {
            playTracks(selectedTracks)
        }

        Button("Add to Queue") {
            QueueManager.shared.addToQueue(selectedTracks)
        }

        Button("Play Next") {
            QueueManager.shared.insertNext(selectedTracks)
        }

        Divider()

        Button("Remove from \(displayName)") {
            for trackId in trackIds {
                removeFromPlaylist(trackId: trackId)
            }
        }

        Divider()

        AddToPlaylistMenu(tracks: selectedTracks)
    }

    // MARK: - Table Columns

    private var trackNumberColumn: some TableColumnContent<Track, Never> {
        TableColumn("#") { track in
            Text(track.trackNumber.map { String($0) } ?? "")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .width(min: 40, ideal: 50, max: 60)
    }

    private var titleColumn: some TableColumnContent<Track, KeyPathComparator<Track>> {
        TableColumn("Title", value: \.title) { track in
            HStack(spacing: 8) {
                if track.isFavorite {
                    Image(systemName: Icons.starFill)
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
                Text(track.title)
            }
        }
        .width(min: 150, ideal: 250)
    }

    private var artistColumn: some TableColumnContent<Track, KeyPathComparator<Track>> {
        TableColumn("Artist", value: \.displayArtist) { track in
            Text(track.displayArtist)
                .foregroundStyle(.secondary)
        }
        .width(min: 120, ideal: 180)
    }

    private var albumColumn: some TableColumnContent<Track, KeyPathComparator<Track>> {
        TableColumn("Album", value: \.displayAlbum) { track in
            Text(track.displayAlbum)
                .foregroundStyle(.secondary)
        }
        .width(min: 120, ideal: 200)
    }

    private var yearColumn: some TableColumnContent<Track, Never> {
        TableColumn("Year") { track in
            if let year = track.year {
                Text(String(year))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("")
            }
        }
        .width(min: 50, ideal: 60, max: 70)
    }

    private var durationColumn: some TableColumnContent<Track, KeyPathComparator<Track>> {
        TableColumn("Duration", value: \.duration) { track in
            Text(track.formattedDuration)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .width(min: 60, ideal: 80, max: 90)
    }
}
