import SwiftUI

struct ArtistGrid: View {
    let artists: [Artist]?

    // Use adaptive columns that automatically adjust based on available width
    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)]

    @State private var allArtists: [Artist] = []
    private let artistDAO = ArtistDAO()

    init(artists: [Artist]? = nil) {
        self.artists = artists
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(displayArtists, id: \.id) { artist in
                ArtistGridItem(artist: artist)
            }
        }
        .onAppear {
            if artists == nil {
                loadAllArtists()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
            if artists == nil {
                loadAllArtists()
            }
        }
    }

    private var displayArtists: [Artist] {
        artists ?? allArtists
    }

    private func loadAllArtists() {
        allArtists = artistDAO.getAll()
    }
}

struct ArtistGridItem: View {
    let artist: Artist
    @State private var artwork: NSImage?
    @State private var tracksInfo: ArtistTracksInfo?
    @State private var isHovered = false
    @State private var artworkTask: Task<Void, Never>?

    private let trackDAO = TrackDAO()

    private let artworkManager = ArtworkManager.shared

    var body: some View {
        NavigationLink(value: artist) {
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
                            playArtist()
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

 

                // Artist name
                //if let artist = artist.name {
                    Text(artist.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                //}

                //}
                //.frame(width: 180, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
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
    }

    private var albumContextMenu: some View {
        Group {
            Button("Play Now") {
                playArtist()
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
        artworkTask?.cancel()
        artworkTask = Task {
            // Debounce: skip items that flash by during fast scroll
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            guard !Task.isCancelled else { return }

            do {
                let image = try await artworkManager.fetchArtistArtwork(for: artist)
                guard !Task.isCancelled else { return }
                artwork = image
            } catch {
                // Artwork not found — leave placeholder
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

    private func addToQueue() {
        let trackDAO = TrackDAO()
        let tracks = trackDAO.getByArtistId(artistId: artist.id)
        QueueManager.shared.addToQueue(tracks)
    }

    private func playNext() {
        let trackDAO = TrackDAO()
        let tracks = trackDAO.getByArtistId(artistId: artist.id)
        QueueManager.shared.insertNext(tracks)
    }
}
