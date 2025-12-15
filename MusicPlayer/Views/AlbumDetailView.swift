import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @State private var artwork: NSImage?
    @State private var artist: Artist?
    @State private var dominantColor: Color?
    private let artworkManager = ArtworkManager.shared
    private let artistDAO = ArtistDAO()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Background with dominant color
                if let dominantColor = dominantColor {
                    dominantColor.opacity(0.15)
                        .ignoresSafeArea()
                }

                VStack(spacing: 0) {
                    headerSection
                    AlbumSongsView(album: album)
                }
            }
        }
        .onAppear() {
            loadArtwork()
            loadArtist()
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 24) {
                // Larger artwork with shadow
                Group {
                    if let artwork = artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Color.secondary.opacity(0.2)

                            Image(systemName: Icons.opticalDiscFill)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.secondary.opacity(0.5))
                                .padding(40)
                        }
                    }
                }
                .frame(width: 200, height: 200)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)

                VStack (alignment: .leading, spacing: 14) {
                    // "ALBUM" label
                    Text("ALBUM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.semibold)
                        .textCase(.uppercase)

                    // Album title
                    Text(album.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .lineLimit(2)

                    // Artist name
                    if let artistName = album.artistName {
                        Text(artistName)
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }

                    // Metadata row
                    HStack(spacing: 8) {
                        if let year = album.year, year > 0 {
                            Text("\(year)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("•")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Text("\(album.trackCount) \(album.trackCount == 1 ? "track" : "tracks")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(album.formattedDuration)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)

                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: { playAlbum() }) {
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

                        Button(action: { shuffleAlbum() }) {
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
                    }
                    .padding(.top, 8)
                }

                Spacer()
            }
            .background(.regularMaterial)
            .padding(16)
    }
    
    private func loadArtwork() {
        artworkManager.fetchAlbumArtwork(for: album) { result in
            if case .success(let image) = result {
                DispatchQueue.main.async {
                    artwork = image
                    updateDominantColor(from: image)
                }
            }
        }
    }

    private func updateDominantColor(from artwork: NSImage?) {
        guard let artwork = artwork else {
            withAnimation(.easeInOut(duration: 0.3)) {
                dominantColor = nil
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let extractedColor = ColorExtractor.extractDominantColor(from: artwork)
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    dominantColor = extractedColor
                }
            }
        }
    }

    private func loadArtist() {
        if let artistId = album.artistId {
            artist = artistDAO.getById(id: artistId)
        }
    }

    private func playAlbum() {
        let trackDAO = TrackDAO()
        let tracks = trackDAO.getByAlbumId(albumId: album.id)

        guard !tracks.isEmpty else { return }

        QueueManager.shared.setQueue(tracks, startIndex: 0)
        PlayerManager.shared.play(track: tracks[0])
    }

    private func shuffleAlbum() {
        let trackDAO = TrackDAO()
        var tracks = trackDAO.getByAlbumId(albumId: album.id)

        guard !tracks.isEmpty else { return }

        tracks.shuffle()
        QueueManager.shared.setQueue(tracks, startIndex: 0)
        QueueManager.shared.setShuffleEnabled(true)
        PlayerManager.shared.play(track: tracks[0])
    }

    private func addToQueue() {
        let trackDAO = TrackDAO()
        let tracks = trackDAO.getByAlbumId(albumId: album.id)
        QueueManager.shared.addToQueue(tracks)
    }
}


