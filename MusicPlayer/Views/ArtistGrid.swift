import SwiftUI

struct ArtistGrid: View {
    let artists: [Artist]?
    let columns: [GridItem]

    @State private var allArtists: [Artist] = []
    private let artistDAO = ArtistDAO()

    init(artist: [Artist]? = nil, columnCount: Int = 5) {
        self.artists = artist
        self.columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
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
    
    private let trackDAO = TrackDAO()

    private let artworkManager = ArtworkManager.shared

    var body: some View {
        NavigationLink(destination: ArtistDetailView(artist: artist)) {
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 180, alignment: .leading)
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

            Divider()

            Button("Show Album Info") {
                // TODO: Show album detail view
            }
        }
    }

    private func loadArtwork() {
        
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
//        artworkManager.fetchAlbumArtwork(for: album) { result in
//            if case .success(let image) = result {
//                DispatchQueue.main.async {
//                    artwork = image
//                }
//            }
//        }
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
