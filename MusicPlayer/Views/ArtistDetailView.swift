import SwiftUI

struct ArtistDetailView: View {
    let artist: Artist
    @State private var artwork: NSImage?
    @State private var tracksInfo: ArtistTracksInfo?
    @State private var albums: [Album] = []
    @State private var showAllAlbums = false
    @State private var addedToQueueMessage: String?
    @State private var hasLoadedData = false
    @State private var topTracks: [Track]? = nil

    private let artworkManager = ArtworkManager.shared
    private let trackDAO = TrackDAO()
    private let albumDAO = AlbumDAO()

    private let initialAlbumCount = 6

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                // Larger artist image with circular mask
                Group {
                    if let artwork = artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ArtistInitialPlaceholder(name: artist.name)
                    }
                }
                .frame(width: 200, height: 200)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)

                // Artist info
                VStack (alignment: .leading, spacing: 14) {
                    // Artist name
                    Text(artist.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .lineLimit(2)

                    // Stats
                    HStack(spacing: 8) {
                        Text("\(albums.count) \(albums.count == 1 ? "album" : "albums")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let tracksInfo = tracksInfo {
                            Text("\(tracksInfo.trackCount) \(tracksInfo.trackCount == 1 ? "track" : "tracks")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("•")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(tracksInfo.formattedDuration)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(artist.trackCount) \(artist.trackCount == 1 ? "track" : "tracks")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)

                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: { playArtist() }) {
                            HStack(spacing: 6) {
                                Image(systemName: Icons.playFill)
                                    .font(.system(size: 14))
                                Text("Play")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: { shuffleArtist() }) {
                            HStack(spacing: 6) {
                                Image(systemName: Icons.shuffleFill)
                                    .font(.system(size: 14))
                                Text("Shuffle")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { addToQueue() }) {
                            HStack(spacing: 6) {
                                Image(systemName: Icons.plusCircle)
                                    .font(.system(size: 14))
                                Text("Add to Queue")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { playNext() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "text.insert")
                                    .font(.system(size: 14))
                                Text("Play Next")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 8)
                }

                Spacer()
            }
            .padding(16)

            // Artist albums/tracks view
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if tracksInfo != nil {
                        // Display albums by this artist
                        if !albums.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Albums")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)

                                let displayedAlbums = showAllAlbums ? albums : Array(albums.prefix(initialAlbumCount))
                                AlbumGrid(albums: displayedAlbums)
                                    .padding(.horizontal)

                                if albums.count > initialAlbumCount {
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            showAllAlbums.toggle()
                                        }
                                    }) {
                                        Text(showAllAlbums ? "Show Less" : "Show All \(albums.count) Albums")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal)
                                }
                            }
                        }

                        // Display top tracks (only if there's actual play data)
                        if let topTracks = topTracks, !topTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Top Tracks")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)

                                VStack(spacing: 0) {
                                    ForEach(Array(topTracks.prefix(10).enumerated()), id: \.element.id) { index, track in
                                        TrackRow(track: track, index: index + 1)
                                        if index < min(topTracks.count, 10) - 1 {
                                            Divider().padding(.leading, 54)
                                        }
                                    }
                                }
                            }
                        }

                        // Display all tracks
                        VStack(alignment: .leading, spacing: 12) {
                            Text("All Songs")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)

                            ArtistSongsView(artist: artist)
                        }
                    } else if !hasLoadedData {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("No tracks found for this artist")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.vertical)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = addedToQueueMessage {
                Text(message)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: addedToQueueMessage)
            }
        }
        .onAppear() {
            loadArtistData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
            loadArtistData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.trackMetadataChanged)) { _ in
            loadArtistData()
        }
    }

    private func loadArtistData() {
        // Load artist artwork
        artworkManager.fetchArtistArtwork(for: artist) { result in
            if case .success(let image) = result {
                DispatchQueue.main.async {
                    artwork = image
                }
            }
        }

        // Load albums and tracks info
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedAlbums = albumDAO.getByArtistId(artistId: artist.id)
            let info = trackDAO.getArtistTracksInfo(artistId: artist.id)
            DispatchQueue.main.async {
                albums = loadedAlbums
                tracksInfo = info
                hasLoadedData = true
                refreshTopTracks(from: info)
            }
        }
    }

    private func refreshTopTracks(from info: ArtistTracksInfo?) {
        guard let info = info else {
            topTracks = nil
            return
        }
        let playedTracks = info.tracks.filter { $0.playCount > 0 }
        topTracks = playedTracks.isEmpty ? nil : playedTracks.sorted { $0.playCount > $1.playCount }
    }

    private func playArtist() {
        guard let tracksInfo = tracksInfo, !tracksInfo.tracks.isEmpty else { return }

        QueueManager.shared.setQueue(tracksInfo.tracks, startIndex: 0)
        PlayerManager.shared.play(track: tracksInfo.tracks[0])
    }

    private func shuffleArtist() {
        guard let tracksInfo = tracksInfo, !tracksInfo.tracks.isEmpty else { return }

        var shuffledTracks = tracksInfo.tracks
        shuffledTracks.shuffle()
        QueueManager.shared.setQueue(shuffledTracks, startIndex: 0)
        QueueManager.shared.setShuffleEnabled(true)
        PlayerManager.shared.play(track: shuffledTracks[0])
    }

    private func addToQueue() {
        guard let tracksInfo = tracksInfo, !tracksInfo.tracks.isEmpty else { return }
        QueueManager.shared.addToQueue(tracksInfo.tracks)
        addedToQueueMessage = "\(tracksInfo.tracks.count) track\(tracksInfo.tracks.count == 1 ? "" : "s") added to queue"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            addedToQueueMessage = nil
        }
    }

    private func playNext() {
        guard let tracksInfo = tracksInfo, !tracksInfo.tracks.isEmpty else { return }
        QueueManager.shared.insertNext(tracksInfo.tracks)
        addedToQueueMessage = "\(tracksInfo.tracks.count) track\(tracksInfo.tracks.count == 1 ? "" : "s") will play next"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            addedToQueueMessage = nil
        }
    }

}

// Simple track row for artist detail view
struct TrackRow: View {
    let track: Track
    let index: Int
    @State private var tracksToEdit: [Track]?

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)

                if let album = track.albumTitle {
                    Text(album)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(track.duration.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: { PlayerManager.shared.play(track: track) }) {
                Image(systemName: Icons.playFill)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .help("Play track")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            PlayerManager.shared.play(track: track)
        }
        .contextMenu {
            Button("Play Now") {
                PlayerManager.shared.play(track: track)
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

            Menu("Add to Playlist") {
                Button("Create New Playlist...") {
                    PlaylistMenuHelper.shared.showCreatePlaylistDialog(tracks: [track])
                }
                let playlists = PlaylistDAO().getAll()
                if !playlists.isEmpty {
                    Divider()
                    ForEach(playlists, id: \.id) { playlist in
                        Button(playlist.name) {
                            let dao = PlaylistDAO()
                            dao.addTrack(playlistId: playlist.id, trackId: track.id)
                            NotificationCenter.default.post(
                                name: Constants.Notifications.playlistContentChanged,
                                object: nil,
                                userInfo: ["playlistId": playlist.id]
                            )
                        }
                    }
                }
            }

            Divider()

            Button("Edit Info...") {
                tracksToEdit = [track]
            }

            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: track.filePath)])
            }
        }
        .sheet(isPresented: Binding(get: { tracksToEdit != nil }, set: { if !$0 { tracksToEdit = nil } })) {
            if let tracks = tracksToEdit {
                TrackEditorView(tracks: tracks)
            }
        }
    }
}


