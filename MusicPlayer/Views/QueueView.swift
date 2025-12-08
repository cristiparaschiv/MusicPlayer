import SwiftUI

struct QueueView: View {
    @ObservedObject var nowPlaying = NowPlayingManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Queue", systemImage: Icons.musicNoteList)
                    .font(.headline)

                Spacer()

                Text("\(nowPlaying.queue.count) tracks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Queue list
            if nowPlaying.queue.isEmpty {
                emptyQueueView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(nowPlaying.queue.enumerated()), id: \.element.id) { index, track in
                            QueueTrackRow(
                                track: track,
                                index: index,
                                isCurrentTrack: index == nowPlaying.currentTrackIndex,
                                onTap: {
                                    playTrack(at: index)
                                }
                            )
                            .background(index == nowPlaying.currentTrackIndex ? Color.accentColor.opacity(0.1) : Color.clear)

                            if index < nowPlaying.queue.count - 1 {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 280)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Empty State

    private var emptyQueueView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: Icons.musicNoteList)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundStyle(.secondary.opacity(0.5))

            Text("Queue is Empty")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text("Add tracks to start playing")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func playTrack(at index: Int) {
        if index < nowPlaying.queue.count {
            let track = nowPlaying.queue[index]
            _ = QueueManager.shared.skipToTrack(at: index)
            nowPlaying.play(track: track)
        }
    }
}

// MARK: - Queue Track Row

struct QueueTrackRow: View {
    let track: Track
    let index: Int
    let isCurrentTrack: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Track number or playing indicator
                if isCurrentTrack {
                    Image(systemName: "waveform")
                        .foregroundStyle(.blue)
                        .frame(width: 30)
                } else {
                    Text("\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                }

                // Track info
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.subheadline)
                        .fontWeight(isCurrentTrack ? .semibold : .regular)
                        .foregroundStyle(isCurrentTrack ? .blue : .primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(track.displayArtist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let album = track.albumTitle {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(album)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Duration
                Text(track.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play Now") {
                onTap()
            }

            Divider()

            Button(track.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                PlayerManager.shared.toggleFavorite(track: track)
            }

            Divider()

            AddToPlaylistMenu(tracks: [track])

            Divider()

            Button("Remove from Queue") {
                QueueManager.shared.removeTrack(at: index)
            }

            Divider()

            Button("Show in Finder") {
                let url = URL(fileURLWithPath: track.filePath)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}
