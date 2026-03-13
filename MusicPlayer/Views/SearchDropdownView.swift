import SwiftUI

struct SearchDropdownView: View {
    @ObservedObject var searchManager: SearchManager
    var onTrackSelected: (Track) -> Void
    var onAlbumSelected: (Album) -> Void
    var onArtistSelected: (Artist) -> Void

    private var tracks: [Track] {
        Array(searchManager.searchResults.tracks.prefix(5))
    }

    private var albums: [Album] {
        Array(searchManager.searchResults.albums.prefix(3))
    }

    private var artists: [Artist] {
        Array(searchManager.searchResults.artists.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if searchManager.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else if searchManager.searchResults.isEmpty {
                Text("No results for \"\(searchManager.searchText)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Tracks
                        if !tracks.isEmpty {
                            sectionHeader("Tracks", icon: Icons.musicNote, count: searchManager.searchResults.tracks.count)
                            ForEach(tracks, id: \.id) { track in
                                Button { onTrackSelected(track) } label: {
                                    DropdownTrackRow(track: track)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Albums
                        if !albums.isEmpty {
                            if !tracks.isEmpty {
                                Divider().padding(.vertical, 4)
                            }
                            sectionHeader("Albums", icon: Icons.opticalDiscFill, count: searchManager.searchResults.albums.count)
                            ForEach(albums, id: \.id) { album in
                                Button { onAlbumSelected(album) } label: {
                                    DropdownAlbumRow(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Artists
                        if !artists.isEmpty {
                            if !tracks.isEmpty || !albums.isEmpty {
                                Divider().padding(.vertical, 4)
                            }
                            sectionHeader("Artists", icon: Icons.personFill, count: searchManager.searchResults.artists.count)
                            ForEach(artists, id: \.id) { artist in
                                Button { onArtistSelected(artist) } label: {
                                    DropdownArtistRow(artist: artist)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 350)
        .frame(maxHeight: 400)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func sectionHeader(_ title: String, icon: String, count: Int = 0) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
            if count > 5 {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - Row Views

private struct DropdownTrackRow: View {
    let track: Track
    @State private var artwork: NSImage?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Artwork thumbnail
            Group {
                if let artwork = artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.secondary.opacity(0.15)
                        Image(systemName: Icons.musicNote)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 28, height: 28)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                if let artist = track.artistName {
                    Text(artist)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(track.formattedDuration)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            ArtworkManager.shared.fetchArtworkFromTrack(track) { result in
                if case .success(let image) = result {
                    DispatchQueue.main.async {
                        artwork = image
                    }
                }
            }
        }
    }
}

private struct DropdownAlbumRow: View {
    let album: Album
    @State private var artwork: NSImage?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let artwork = artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.secondary.opacity(0.15)
                        Image(systemName: Icons.opticalDiscFill)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 28, height: 28)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 1) {
                Text(album.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(album.artistName ?? "\(album.trackCount) tracks")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(album.trackCount) tracks")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            ArtworkManager.shared.fetchAlbumArtwork(for: album) { result in
                if case .success(let image) = result {
                    DispatchQueue.main.async {
                        artwork = image
                    }
                }
            }
        }
    }
}

private struct DropdownArtistRow: View {
    let artist: Artist
    @State private var artwork: NSImage?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let artwork = artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.secondary.opacity(0.15)
                        Image(systemName: Icons.personFill)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(artist.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text("\(artist.trackCount) tracks")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            ArtworkManager.shared.fetchArtistArtwork(for: artist) { result in
                if case .success(let image) = result {
                    DispatchQueue.main.async {
                        artwork = image
                    }
                }
            }
        }
    }
}
