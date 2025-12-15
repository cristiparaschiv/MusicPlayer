import SwiftUI

struct AlbumGrid: View {
    let albums: [Album]?

    // Use adaptive columns that automatically adjust based on available width
    // Each item is ~180px wide, so this ensures proper spacing without overlap
    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)]

    @State private var allAlbums: [Album] = []
    private let albumDAO = AlbumDAO()

    init(albums: [Album]? = nil) {
        self.albums = albums
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(displayAlbums, id: \.id) { album in
                AlbumGridItem(album: album)
            }
        }
        .onAppear {
            if albums == nil {
                loadAllAlbums()
            }
        }
    }

    private var displayAlbums: [Album] {
        albums ?? allAlbums
    }

    private func loadAllAlbums() {
        allAlbums = albumDAO.getAll()
    }
}

struct AlbumGridItem: View {
    let album: Album
    @State private var artwork: NSImage?
    @State private var isHovered = false

    private let artworkManager = ArtworkManager.shared

    var body: some View {
        NavigationLink(destination: AlbumDetailView(album: album)) {
            VStack(alignment: .leading, spacing: 8) {
                // Album artwork
                ZStack(alignment: .bottomTrailing) {
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
                                    .padding(30)
                            }
                        }
                    }
                    .frame(width: 180, height: 180)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)

                    // Play button overlay on hover
                    if isHovered {
                        Button(action: {
                            playAlbum()
                        }) {
                            Image(systemName: Icons.playCircleFill)
                                .font(.system(size: 48))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }

                // Album title
                Text(album.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 180, alignment: .leading)

                // Artist name
                if let artist = album.artistName {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 180, alignment: .leading)
                }

                // Additional info
                HStack(spacing: 4) {
                    if let year = album.year {
                        Text("\(year)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if album.year != nil, album.trackCount > 0 {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if album.trackCount > 0 {
                        Text("\(album.trackCount) tracks")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 180, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            albumContextMenu
        }
        .onAppear {
            loadArtwork()
        }
    }

    private var albumContextMenu: some View {
        Group {
            Button("Play Now") {
                playAlbum()
            }

            Button("Add to Queue") {
                addToQueue()
            }

            Button("Play Next") {
                playNext()
            }

        }
    }

    private func loadArtwork() {
        artworkManager.fetchAlbumArtwork(for: album) { result in
            if case .success(let image) = result {
                DispatchQueue.main.async {
                    artwork = image
                }
            }
        }
    }

    private func playAlbum() {
        let trackDAO = TrackDAO()
        let tracks = trackDAO.getByAlbumId(albumId: album.id)

        guard !tracks.isEmpty else { return }

        QueueManager.shared.setQueue(tracks, startIndex: 0)
        PlayerManager.shared.play(track: tracks[0])
    }

    private func addToQueue() {
        let trackDAO = TrackDAO()
        let tracks = trackDAO.getByAlbumId(albumId: album.id)
        QueueManager.shared.addToQueue(tracks)
    }

    private func playNext() {
        let trackDAO = TrackDAO()
        let tracks = trackDAO.getByAlbumId(albumId: album.id)
        QueueManager.shared.insertNext(tracks)
    }
}
