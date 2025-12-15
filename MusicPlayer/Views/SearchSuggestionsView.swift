import SwiftUI

struct SearchSuggestionsView: View {
    @EnvironmentObject var searchManager: SearchManager
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if searchManager.isSearching {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Searching...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if !searchManager.searchResults.isEmpty {
                // Tracks section
                if !searchManager.searchResults.tracks.isEmpty {
                    suggestionSection(
                        title: "Tracks",
                        icon: Icons.musicNote,
                        items: Array(searchManager.searchResults.tracks.prefix(5))
                    )
                }

                // Albums section
                if !searchManager.searchResults.albums.isEmpty {
                    suggestionSection(
                        title: "Albums",
                        icon: Icons.opticalDiscFill,
                        items: Array(searchManager.searchResults.albums.prefix(5))
                    )
                }

                // Artists section
                if !searchManager.searchResults.artists.isEmpty {
                    suggestionSection(
                        title: "Artists",
                        icon: Icons.personFill,
                        items: Array(searchManager.searchResults.artists.prefix(5))
                    )
                }

                // See All Results button
                if searchManager.searchResults.hasMoreResults {
                    Divider()
                    Button(action: {
                        selection = .search
                    }) {
                        HStack {
                            Image(systemName: Icons.magnifyingGlass)
                            Text("See All Results")
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            } else if !searchManager.searchText.isEmpty {
                Text("No results found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func suggestionSection<T>(title: String, icon: String, items: [T]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Items
            ForEach(items.indices, id: \.self) { index in
                if let track = items[index] as? Track {
                    trackSuggestionRow(track)
                } else if let album = items[index] as? Album {
                    albumSuggestionRow(album)
                } else if let artist = items[index] as? Artist {
                    artistSuggestionRow(artist)
                }
            }

            if items.count < itemCount(for: title) {
                Button(action: {
                    selection = .search
                }) {
                    HStack {
                        Text("Show \(itemCount(for: title) - items.count) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func trackSuggestionRow(_ track: Track) -> some View {
        Button(action: {
            handleTrackClick(track)
        }) {
            HStack(spacing: 8) {
                Image(systemName: Icons.musicNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.caption)
                        .lineLimit(1)

                    if let artist = track.artistName {
                        Text(artist)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func albumSuggestionRow(_ album: Album) -> some View {
        NavigationLink(destination: AlbumDetailView(album: album)) {
            HStack(spacing: 8) {
                Image(systemName: Icons.opticalDiscFill)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.caption)
                        .lineLimit(1)

                    if let artist = album.artistName {
                        Text(artist)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func artistSuggestionRow(_ artist: Artist) -> some View {
        ArtistSuggestionRow(artist: artist)
    }

    private func handleTrackClick(_ track: Track) {
        if PlayerManager.shared.isPlaying {
            // If something is playing, add to queue
            QueueManager.shared.addToQueue([track])
        } else {
            // If nothing is playing, play the track
            PlayerManager.shared.play(track: track)
        }
    }

    private func itemCount(for section: String) -> Int {
        switch section {
        case "Tracks":
            return searchManager.searchResults.tracks.count
        case "Albums":
            return searchManager.searchResults.albums.count
        case "Artists":
            return searchManager.searchResults.artists.count
        default:
            return 0
        }
    }
}

struct ArtistSuggestionRow: View {
    let artist: Artist
    @State private var artwork: NSImage?

    private let artworkManager = ArtworkManager.shared

    var body: some View {
        NavigationLink(destination: ArtistDetailView(artist: artist)) {
            HStack(spacing: 8) {
                // Artist artwork thumbnail
                Group {
                    if let artwork = artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Color.secondary.opacity(0.2)

                            Image(systemName: Icons.personFill)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                    }
                }
                .frame(width: 24, height: 24)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                        .font(.caption)
                        .lineLimit(1)

                    Text("\(artist.trackCount) tracks")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
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

