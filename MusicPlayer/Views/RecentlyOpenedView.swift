import SwiftUI

struct RecentlyOpenedView: View {
    @ObservedObject private var manager = ExternalTrackManager.shared
    @State private var showingClearAlert = false
    @State private var tracksToEdit: [Track]?

    private var totalDuration: TimeInterval {
        manager.tracks.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Color.orange.opacity(0.3)
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                }
                .frame(width: 100, height: 100)
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recently Opened")
                        .font(.largeTitle)
                        .bold()

                    HStack(spacing: 8) {
                        Text("\(manager.tracks.count) \(manager.tracks.count == 1 ? "song" : "songs")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if !manager.tracks.isEmpty {
                            Text("\u{2022}")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(totalDuration.formattedDuration)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        if !manager.tracks.isEmpty {
                            Button(action: playAll) {
                                HStack(spacing: 4) {
                                    Image(systemName: Icons.playFill)
                                    Text("Play All")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)

                            Button(action: { showingClearAlert = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: Icons.trash)
                                    Text("Clear")
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .background(.regularMaterial)

            Divider()

            // Content
            if manager.tracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No files opened yet")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Drag audio files here or use Open With in Finder")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackTableView(
                    tracks: manager.tracks,
                    config: TrackTableConfig(
                        showRemoveFromPlaylist: true,
                        removeFromPlaylistLabel: "Remove from Recently Opened",
                        onRemoveFromPlaylist: { trackIDs in
                            for id in trackIDs {
                                manager.removeTrack(id: id)
                            }
                        },
                        onEditTrack: { tracksToEdit = $0 }
                    ),
                    onPlayTrack: { track, allTracks in
                        if let index = allTracks.firstIndex(where: { $0.id == track.id }) {
                            QueueManager.shared.setQueue(allTracks, startIndex: index)
                            PlayerManager.shared.play(track: track)
                        }
                    }
                )
            }
        }
        .alert("Clear Recently Opened", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                manager.clearAll()
            }
        } message: {
            Text("Are you sure you want to clear all recently opened files?")
        }
        .sheet(isPresented: Binding(get: { tracksToEdit != nil }, set: { if !$0 { tracksToEdit = nil } })) {
            if let tracks = tracksToEdit {
                TrackEditorView(tracks: tracks)
            }
        }
    }

    private func playAll() {
        guard !manager.tracks.isEmpty else { return }
        QueueManager.shared.setQueue(manager.tracks, startIndex: 0)
        PlayerManager.shared.play(track: manager.tracks[0])
    }
}
