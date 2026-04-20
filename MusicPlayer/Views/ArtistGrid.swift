import SwiftUI

struct ArtistGrid: View {
    let artists: [Artist]?

    // Use adaptive columns that automatically adjust based on available width
    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)]

    @State private var allArtists: [Artist] = []
    @State private var hasMore = true
    private let pageSize = 100
    private let artistDAO = ArtistDAO()

    init(artists: [Artist]? = nil) {
        self.artists = artists
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(displayArtists, id: \.id) { artist in
                ArtistGridItem(artist: artist)
                    .onAppear {
                        if artists == nil, artist.id == allArtists.last?.id {
                            loadMore()
                        }
                    }
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
        allArtists = artistDAO.getPage(offset: 0, limit: pageSize)
        hasMore = allArtists.count >= pageSize
    }

    private func loadMore() {
        guard hasMore else { return }
        let next = artistDAO.getPage(offset: allArtists.count, limit: pageSize)
        allArtists.append(contentsOf: next)
        hasMore = next.count >= pageSize
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
                    Group {
                        if let artwork = artwork {
                            Color.secondary.opacity(0.2)
                                .overlay {
                                    Image(nsImage: artwork)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                        } else {
                            ArtistInitialPlaceholder(name: artist.name)
                        }
                    }
                        .aspectRatio(1, contentMode: .fit)
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

/// Typographic placeholder shown when an artist has no artwork.
/// Produces a stable, name-derived gradient with the artist's initial overlaid.
struct ArtistInitialPlaceholder: View {
    let name: String

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(
                    colors: gradientColors(for: name),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(initial(for: name))
                    .font(.system(size: side * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            }
        }
    }

    private func initial(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private func gradientColors(for name: String) -> [Color] {
        let hash = stableHash(name)
        let hue = Double(hash % 360) / 360.0
        let baseSat = 0.55
        let baseBright = 0.55
        let base = Color(hue: hue, saturation: baseSat, brightness: baseBright)
        let accent = Color(
            hue: fmod(hue + 0.06, 1.0),
            saturation: min(baseSat + 0.15, 0.9),
            brightness: min(baseBright + 0.15, 0.85)
        )
        return [base, accent]
    }

    /// FNV-1a — small, stable, not cryptographic. Used only to pick a hue.
    private func stableHash(_ s: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in s.lowercased().utf8 {
            h ^= UInt64(byte)
            h &*= 0x100000001b3
        }
        return Int(h % UInt64(Int.max))
    }
}
