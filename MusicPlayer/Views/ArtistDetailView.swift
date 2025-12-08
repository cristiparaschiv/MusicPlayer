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
            HStack(alignment: .top, spacing: 20) {
                // Artist artwork
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
                                .padding(30)
                        }
                    }
                }
                .frame(width: 120, height: 120)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)

                // Artist info
                VStack (alignment: .leading, spacing: 12) {
                    Text("Artist")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)

                    Text(artist.name)
                        .font(.title)
                        .fontWeight(.bold)
                        .lineLimit(2)

                    HStack {
                        if let tracksInfo = tracksInfo {
                            Text("\(tracksInfo.trackCount) \(tracksInfo.trackCount == 1 ? "song" : "songs")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("•")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(tracksInfo.formattedDuration)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(artist.trackCount) \(artist.trackCount == 1 ? "song" : "songs")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 10) {
                        Button(action: { playArtist() }) {
                            Image(systemName: Icons.playFill)
                                .font(.system(size: 12))
                            Text("Play")
                                .font(.system(size: 13))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(6)
                }

                Spacer()
            }
            .background(.regularMaterial)
            .padding(10)

            // Artist albums/tracks view
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if tracksInfo != nil {
                        // Display albums by this artist
                        let albums = albumDAO.getByArtistId(artistId: artist.id)
                        if !albums.isEmpty {
                            Text("Albums")
                                .font(.headline)
                                .padding(.horizontal)

                            AlbumGrid(albums: albums, columnCount: 5)
                                .padding(.horizontal)
                        }

                        // Display all tracks
                        Text("All Songs")
                            .font(.headline)
                            .padding(.horizontal)

                        ArtistSongsView(artist: artist)
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


