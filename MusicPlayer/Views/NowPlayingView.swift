import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var nowPlaying = NowPlayingManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let track = nowPlaying.currentTrack {
                    // Artwork
                    artworkSection

                    // Track info
                    trackInfoSection(track: track)

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
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Artwork Section

    private var artworkSection: some View {
        Group {
            if nowPlaying.artworkState.isLoading {
                ProgressView()
                    .frame(width: 240, height: 240)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            } else if let artwork = nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 240, height: 240)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            } else {
                Image(systemName: Icons.musicNote)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .frame(width: 240, height: 240)
                    .padding(40)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }

    // MARK: - Track Info Section

    private func trackInfoSection(track: Track) -> some View {
        VStack(spacing: 8) {
            Text(track.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(track.displayArtist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let album = track.albumTitle {
                Text(album)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .italic()
            }

            // Additional info
            HStack(spacing: 16) {
                if let year = track.year {
                    Label("\(year)", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let genre = track.genreName {
                    Label(genre, systemImage: "music.note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Lyrics Section

    private func lyricsSection(track: Track) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Lyrics", systemImage: "text.quote")
                    .font(.headline)

                Spacer()

                if nowPlaying.lyricsState == .idle {
                    Button("Load") {
                        nowPlaying.loadLyrics()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if nowPlaying.lyricsState.isLoading {
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
                ScrollView {
                    Text(lyrics)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
                .padding(.vertical, 8)
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
