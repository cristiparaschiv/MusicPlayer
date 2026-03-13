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
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
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
    @State private var artworkTask: Task<Void, Never>?

    private let artworkManager = ArtworkManager.shared

    var body: some View {
        NavigationLink(value: album) {
            VStack(alignment: .leading, spacing: 8) {
                // Album artwork
                ZStack(alignment: .bottomTrailing) {
                    Color.secondary.opacity(0.2)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if let artwork = artwork {
                                Image(nsImage: artwork)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: Icons.opticalDiscFill)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.secondary.opacity(0.5))
                                    .padding(30)
                            }
                        }
                        .clipped()
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
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Artist name
                if let artist = album.artistName {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityLabel("\(album.title) by \(album.artistName ?? "Unknown Artist")")
        .contextMenu {
            albumContextMenu
        }
        .onAppear {
            loadArtwork()
        }
        .onDisappear {
            artworkTask?.cancel()
            artworkTask = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.artworkDidChange)) { notification in
            if let albumId = notification.userInfo?["albumId"] as? Int64, albumId == album.id {
                artwork = nil
                loadArtwork()
            }
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

            Divider()

            Button("Choose Artwork...") {
                ArtworkPickerWindowManager.shared.show(for: album)
            }
        }
    }

    private func loadArtwork() {
        artworkTask?.cancel()
        artworkTask = Task {
            // Debounce: skip items that flash by during fast scroll
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            guard !Task.isCancelled else { return }

            do {
                let image = try await artworkManager.fetchAlbumArtwork(for: album)
                guard !Task.isCancelled else { return }
                artwork = image
            } catch {
                // Artwork not found — leave placeholder
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
