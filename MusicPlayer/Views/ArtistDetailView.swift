import SwiftUI

struct ArtistDetailView: View {
    let artist: Artist
    @State private var artwork: NSImage?
    @State private var tracksInfo: ArtistTracksInfo?

    private let artworkManager = ArtworkManager.shared
    private let trackDAO = TrackDAO()
    private let albumDAO = AlbumDAO()

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
                        ZStack {
                            Color.secondary.opacity(0.2)

                            Image(systemName: Icons.personFill)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.secondary.opacity(0.5))
                                .padding(50)
                        }
                    }
                }
                .frame(width: 200, height: 200)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)

                // Artist info
                VStack (alignment: .leading, spacing: 14) {
                    // "ARTIST" label
                    Text("ARTIST")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.semibold)
                        .textCase(.uppercase)

                    // Artist name
                    Text(artist.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .lineLimit(2)

                    // Stats
                    HStack(spacing: 8) {
                        let albums = albumDAO.getByArtistId(artistId: artist.id)
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
                                Text("Play All")
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
                    }
                    .padding(.top, 8)
                }

                Spacer()
            }
            .background(.regularMaterial)
            .padding(16)

            // Artist albums/tracks view
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if tracksInfo != nil {
                        // Display albums by this artist
                        let albums = albumDAO.getByArtistId(artistId: artist.id)
                        if !albums.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Albums")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)

                                AlbumGrid(albums: albums)
                                    .padding(.horizontal)
                            }
                        }

                        // Display top tracks (most played)
                        if let topTracks = getTopTracks(), !topTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Top Tracks")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)

                                VStack(spacing: 0) {
                                    ForEach(Array(topTracks.prefix(10).enumerated()), id: \.element.id) { index, track in
                                        TrackRow(track: track, index: index + 1)
                                            .background(Color(nsColor: .controlBackgroundColor).opacity(index % 2 == 0 ? 0 : 0.3))
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
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.vertical)
            }
        }
        .onAppear() {
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

        // Load tracks info
        DispatchQueue.global(qos: .userInitiated).async {
            let info = trackDAO.getArtistTracksInfo(artistId: artist.id)
            DispatchQueue.main.async {
                tracksInfo = info
            }
        }
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

    private func getTopTracks() -> [Track]? {
        guard let tracksInfo = tracksInfo else { return nil }

        // Sort tracks by play count (descending)
        return tracksInfo.tracks.sorted { $0.playCount > $1.playCount }
    }
}

// Simple track row for artist detail view
struct TrackRow: View {
    let track: Track
    let index: Int

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
        }
    }
}


