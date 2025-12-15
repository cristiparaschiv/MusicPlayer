import SwiftUI

struct SearchResultsView: View {
    @EnvironmentObject var searchManager: SearchManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if searchManager.isSearching {
                    HStack {
                        ProgressView()
                        Text("Searching...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if searchManager.searchResults.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: Icons.magnifyingGlass)
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        if searchManager.searchText.isEmpty {
                            Text("Enter a search term")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No results found")
                                .font(.title3)
                                .foregroundStyle(.secondary)

                            Text("Try searching for a track, album, or artist")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        // Tracks section
                        if !searchManager.searchResults.tracks.isEmpty {
                            tracksSection
                        }

                        // Albums section
                        if !searchManager.searchResults.albums.isEmpty {
                            albumsSection
                        }

                        // Artists section
                        if !searchManager.searchResults.artists.isEmpty {
                            artistsSection
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Search Results")
    }

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: Icons.musicNote)
                    .font(.title3)
                Text("Tracks")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("(\(searchManager.searchResults.tracks.count))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(searchManager.searchResults.tracks, id: \.id) { track in
                    SearchTrackRow(track: track)
                    if track.id != searchManager.searchResults.tracks.last?.id {
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: Icons.opticalDiscFill)
                    .font(.title3)
                Text("Albums")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("(\(searchManager.searchResults.albums.count))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 5), spacing: 20) {
                ForEach(searchManager.searchResults.albums, id: \.id) { album in
                    AlbumGridItem(album: album)
                }
            }
        }
    }

    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: Icons.personFill)
                    .font(.title3)
                Text("Artists")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("(\(searchManager.searchResults.artists.count))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 5), spacing: 20) {
                ForEach(searchManager.searchResults.artists, id: \.id) { artist in
                    SearchArtistGridItem(artist: artist)
                }
            }
        }
    }
}

struct SearchTrackRow: View {
    let track: Track
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            handleTrackClick()
        }) {
            HStack(spacing: 12) {
                // Track number or icon
                Image(systemName: Icons.musicNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.body)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if let artist = track.artistName {
                            Text(artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if track.artistName != nil && track.albumTitle != nil {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let album = track.albumTitle {
                            Text(album)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                }

                Spacer()

                // Duration
                Text(track.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                // Play/Queue button on hover
                if isHovered {
                    Button(action: {
                        handleTrackClick()
                    }) {
                        Image(systemName: PlayerManager.shared.isPlaying ? Icons.plusCircleFill : Icons.playCircleFill)
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(PlayerManager.shared.isPlaying ? "Add to Queue" : "Play Now")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            trackContextMenu
        }
    }

    private var trackContextMenu: some View {
        Group {
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
        }
    }

    private func handleTrackClick() {
        if PlayerManager.shared.isPlaying {
            // If something is playing, add to queue
            QueueManager.shared.addToQueue([track])
        } else {
            // If nothing is playing, play the track
            PlayerManager.shared.play(track: track)
        }
    }
}

struct SearchArtistGridItem: View {
    let artist: Artist
    @State private var artwork: NSImage?
    @State private var isHovered = false

    private let artworkManager = ArtworkManager.shared

    var body: some View {
        NavigationLink(destination: ArtistDetailView(artist: artist)) {
            VStack(alignment: .leading, spacing: 8) {
                // Artist image
                ZStack {
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
                    .frame(width: 180, height: 180)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                }

                // Artist name
                Text(artist.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 180, alignment: .leading)

                // Track count
                Text("\(artist.trackCount) tracks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 180, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            loadArtwork()
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
    }
}
