import SwiftUI

struct ArtistSongsView: View {
    let artist: Artist
    @State private var tracks: [Track] = []
    @State private var sortedTracks: [Track] = []
    @State private var selection = Set<Track.ID>()
    @State private var sortOrder: [KeyPathComparator<Track>] = []

    private let trackDAO = TrackDAO()

    var body: some View {
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
                // Single track context menu
                singleTrackContextMenu(trackId: items.first!)
            } else {
                // Multiple tracks context menu
                multipleTracksContextMenu(trackIds: items)
            }
        }
        .onChange(of: sortOrder) { _, newOrder in
            applySorting(newOrder)
        }
        .frame(minHeight: 300)
        .onAppear {
            loadTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
            loadTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.trackFavoriteChanged)) { _ in
            // Reload to update favorite icons
            loadTracks()
        }
        // Handle double-click
        .onTapGesture(count: 2) {
            handleDoubleClick()
        }
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

            Button(track.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                PlayerManager.shared.toggleFavorite(track: track)
            }

            Divider()

            AddToPlaylistMenu(tracks: [track])

            Divider()

            Button("Show in Finder") {
                showInFinder(track: track)
            }

            Button("Get Info") {
                // TODO: Show track info
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

        AddToPlaylistMenu(tracks: selectedTracks)
    }

    // MARK: - Actions

    private func loadTracks() {
        tracks = trackDAO.getArtistTracksInfo(artistId: artist.id).tracks
        //tracks = trackDAO.getByAlbumId(albumId: album.id)
        applySorting(sortOrder)
    }

    private func applySorting(_ order: [KeyPathComparator<Track>]) {
        // Always apply default multi-level sorting:
        // 1. Artist (alphabetical)
        // 2. Album Year (chronological)
        // 3. Album Title (if same year)
        // 4. Disc Number
        // 5. Track Number

        sortedTracks = tracks.sorted { track1, track2 in
            // First: Artist name (case-insensitive)
            let artist1 = track1.displayArtist.lowercased()
            let artist2 = track2.displayArtist.lowercased()
            if artist1 != artist2 {
                return artist1 < artist2
            }

            // Second: Album year (chronological, nil values last)
            let year1 = track1.year ?? Int.max
            let year2 = track2.year ?? Int.max
            if year1 != year2 {
                return year1 < year2
            }

            // Third: Album title (alphabetical)
            let album1 = track1.displayAlbum.lowercased()
            let album2 = track2.displayAlbum.lowercased()
            if album1 != album2 {
                return album1 < album2
            }

            // Fourth: Disc number
            let disc1 = track1.discNumber ?? 0
            let disc2 = track2.discNumber ?? 0
            if disc1 != disc2 {
                return disc1 < disc2
            }

            // Fifth: Track number
            let trackNum1 = track1.trackNumber ?? Int.max
            let trackNum2 = track2.trackNumber ?? Int.max
            return trackNum1 < trackNum2
        }

        // Apply any user-selected column sorting on top of default sort
        if !order.isEmpty {
            sortedTracks.sort(using: order)
        }
    }

    private func handleDoubleClick() {
        guard let selectedId = selection.first,
              let track = sortedTracks.first(where: { $0.id == selectedId }) else {
            return
        }

        playTrack(track)
    }

    private func playTrack(_ track: Track) {
        // If queue is empty, set queue with selected track and following tracks
        if QueueManager.shared.isEmpty {
            // Get the index of the selected track in sorted list
            if let index = sortedTracks.firstIndex(where: { $0.id == track.id }) {
                // Set queue with all tracks from this point forward
                let queueTracks = Array(sortedTracks[index...])
                QueueManager.shared.setQueue(queueTracks, startIndex: 0)
                PlayerManager.shared.play(track: track)
            }
        } else {
            // Queue has tracks, just play this track immediately
            QueueManager.shared.setQueue([track], startIndex: 0)
            PlayerManager.shared.play(track: track)
        }
    }

    private func playTracks(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }

        // Sort selected tracks in the same order as they appear in the table
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

// MARK: - Track Conformance


