import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var nowPlaying = NowPlayingManager.shared
    @ObservedObject var progress = PlaybackProgressManager.shared
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let track = nowPlaying.currentTrack {
                    // Artwork (double-click for immersive mode)
                    artworkSection
                        .onTapGesture(count: 2) {
                            ImmersiveWindowManager.shared.show()
                        }
                        .contextMenu {
                            nowPlayingContextMenu(track: track)
                        }

                    // Track info
                    trackInfoSection(track: track)

                    // Star rating
                    StarRatingView(rating: track.rating, size: 16) { newRating in
                        TrackDAO().updateRating(trackId: track.id, rating: newRating)
                    }

                    // Audio info pills
                    audioInfoSection(track: track)

                    Divider()

                    // Lyrics section
                    lyricsSection(track: track)
                } else {
                    // No track playing
                    emptyStateView
                }
            }
            .padding()
        }
        .frame(minWidth: 280)
        .background(.clear)
    }

    // MARK: - Artwork Section

    private var artworkSection: some View {
        Group {
            if nowPlaying.artworkState.isLoading {
                ProgressView()
                    .frame(width: 240, height: 240)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .accessibilityLabel("Loading artwork")
            } else if let artwork = nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 240, height: 240)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .id(nowPlaying.currentTrack?.id)
                    .transition(.opacity)
                    .accessibilityLabel("Album artwork for \(nowPlaying.currentTrack?.albumTitle ?? "current track")")
            } else {
                Image(systemName: Icons.musicNote)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .frame(width: 240, height: 240)
                    .padding(40)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .accessibilityLabel("No artwork available")
            }
        }
        .animation(.easeInOut(duration: 0.4), value: nowPlaying.currentTrack?.id)
    }

    // MARK: - Track Info Section

    private func trackInfoSection(track: Track) -> some View {
        VStack(spacing: 8) {
            Text(track.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .accessibilityLabel("Track title: \(track.title)")

            Text(track.displayArtist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityLabel("Artist: \(track.displayArtist)")

            if let album = track.albumTitle {
                Text(album)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .italic()
                    .accessibilityLabel("Album: \(album)")
            }

            // Additional info
            HStack(spacing: 16) {
                if let year = track.year {
                    Label("\(year)", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Year: \(year)")
                }

                if let genre = track.genreName {
                    Label(genre, systemImage: "music.note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Genre: \(genre)")
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Audio Info Section

    private func audioInfoSection(track: Track) -> some View {
        let caption = audioCaption(track: track)
        let sizeText = fileSizeText(track: track)
        return VStack(alignment: .center, spacing: 4) {
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let sizeText {
                Text(sizeText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Single-line caption: "FLAC · 24-bit / 96 kHz · Stereo · 2,304 kbps"
    private func audioCaption(track: Track) -> String? {
        var segments: [String] = []

        if let format = track.formatName, !format.isEmpty {
            segments.append(format.uppercased())
        }

        var depthRate: [String] = []
        if let bitDepth = track.bitDepth, bitDepth > 0 {
            depthRate.append("\(bitDepth)-bit")
        }
        if let sampleRate = track.sampleRate, sampleRate > 0 {
            let khz = Double(sampleRate) / 1000.0
            if sampleRate >= 1000 {
                let str = khz.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(khz)) kHz"
                    : String(format: "%.1f kHz", khz)
                depthRate.append(str)
            } else {
                depthRate.append("\(sampleRate) Hz")
            }
        }
        if !depthRate.isEmpty {
            segments.append(depthRate.joined(separator: " / "))
        }

        if let channels = track.channelCount {
            switch channels {
            case 1: segments.append("Mono")
            case 2: segments.append("Stereo")
            default: segments.append("\(channels)ch")
            }
        }

        // Only show bitrate if plausible (guards against legacy bad data where
        // the scanner incorrectly divided kbps by 1000).
        if let bitrate = track.bitrate, bitrate >= 32 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            let num = formatter.string(from: NSNumber(value: bitrate)) ?? "\(bitrate)"
            segments.append("\(num) kbps")
        }

        return segments.isEmpty ? nil : segments.joined(separator: " · ")
    }

    private func fileSizeText(track: Track) -> String? {
        let fileSize = track.fileSize
        guard fileSize > 0 else { return nil }
        let mb = Double(fileSize) / (1024.0 * 1024.0)
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(fileSize) / 1024.0
        return String(format: "%.0f KB", kb)
    }

    // MARK: - Lyrics Section

    private func lyricsSection(track: Track) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Lyrics", systemImage: "text.quote")
                    .font(.headline)

                Spacer()

                if nowPlaying.lyricsState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if case .failed = nowPlaying.lyricsState {
                    Button("Retry") {
                        nowPlaying.loadLyrics(force: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Lyrics content
            if nowPlaying.lyricsState.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading lyrics...")
                    Spacer()
                }
                .padding()
            } else if let lyrics = nowPlaying.lyrics {
                SyncedLyricsView(
                    lyrics: lyrics,
                    currentTime: progress.currentTime,
                    isPlaying: nowPlaying.playbackState == .playing
                )
            } else if case .failed(let error) = nowPlaying.lyricsState {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                Text("Lyrics not loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func nowPlayingContextMenu(track: Track) -> some View {
        if let artistId = track.artistId {
            Button("Go to Artist") {
                let artistDAO = ArtistDAO()
                if let artist = artistDAO.getById(id: artistId) {
                    NotificationCenter.default.post(
                        name: Constants.Notifications.navigateToArtist,
                        object: artist
                    )
                }
            }
        }

        if let albumId = track.albumId {
            Button("Go to Album") {
                let albumDAO = AlbumDAO()
                if let album = albumDAO.getById(id: albumId) {
                    NotificationCenter.default.post(
                        name: Constants.Notifications.navigateToAlbum,
                        object: album
                    )
                }
            }
        }

        Divider()

        Button(track.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            PlayerManager.shared.toggleFavorite(track: track)
        }

        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: track.filePath)])
        }

        if let albumId = track.albumId {
            Divider()
            Button("Choose Artwork...") {
                let albumDAO = AlbumDAO()
                if let album = albumDAO.getById(id: albumId) {
                    ArtworkPickerWindowManager.shared.show(for: album)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: Icons.musicNote)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .foregroundStyle(.secondary.opacity(0.5))

            Text("No Track Playing")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text("Select a track to start playing")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}
