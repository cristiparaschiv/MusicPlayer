import SwiftUI

struct ArtistSongsView: View {
    let artist: Artist
    @State private var tracks: [Track] = []
    @State private var trackToEdit: Track?

    private let trackDAO = TrackDAO()

    var body: some View {
        TrackTableView(
            tracks: tracks,
            config: TrackTableConfig(onEditTrack: { trackToEdit = $0 }),
            onPlayTrack: { track, allTracks in
                if let index = allTracks.firstIndex(where: { $0.id == track.id }) {
                    QueueManager.shared.setQueue(allTracks, startIndex: index)
                    PlayerManager.shared.play(track: track)
                }
            }
        )
        .frame(minHeight: 300)
        .onAppear { loadTracks() }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
            loadTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.trackFavoriteChanged)) { _ in
            loadTracks()
        }
        .sheet(item: $trackToEdit) { track in
            TrackEditorView(track: track)
        }
    }

    private func loadTracks() {
        tracks = trackDAO.getArtistTracksInfo(artistId: artist.id).tracks
    }
}
