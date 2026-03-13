import SwiftUI

struct SongsView: View {
    @State private var tracks: [Track] = []
    @State private var tracksToEdit: [Track]?
    @State private var totalCount: Int = 0
    @State private var isLoadingMore = false
    @State private var hasLoadedAll = false

    private let trackDAO = TrackDAO()
    private static let pageSize = 500

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Songs")
                    .font(.largeTitle)
                    .bold()
                Spacer()
                Text("\(totalCount) tracks")
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            if tracks.isEmpty && !isLoadingMore {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("No Songs Yet")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text("Add a music folder in Settings to get started")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            TrackTableView(
                tracks: tracks,
                config: TrackTableConfig(onEditTrack: { tracksToEdit = $0 }),
                onPlayTrack: { track, allTracks in
                    if let index = allTracks.firstIndex(where: { $0.id == track.id }) {
                        QueueManager.shared.setQueue(allTracks, startIndex: index)
                        PlayerManager.shared.play(track: track)
                    }
                },
                onScrollNearEnd: { loadMoreIfNeeded() }
            )
        }
        .onAppear { loadInitialTracks() }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
            loadInitialTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.trackFavoriteChanged)) { _ in
            loadInitialTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.trackMetadataChanged)) { notification in
            refreshChangedTracks(notification)
        }
        .sheet(isPresented: Binding(get: { tracksToEdit != nil }, set: { if !$0 { tracksToEdit = nil } })) {
            if let tracks = tracksToEdit {
                TrackEditorView(tracks: tracks)
            }
        }
    }

    private func loadInitialTracks() {
        DispatchQueue.global(qos: .userInitiated).async {
            let count = trackDAO.getTotalCount()
            let loaded = trackDAO.getAll(limit: Self.pageSize)
            DispatchQueue.main.async {
                totalCount = count
                tracks = loaded
                hasLoadedAll = loaded.count >= count
                isLoadingMore = false
            }
        }
    }

    private func loadMoreIfNeeded() {
        guard !isLoadingMore && !hasLoadedAll else { return }
        isLoadingMore = true

        let currentOffset = tracks.count
        DispatchQueue.global(qos: .userInitiated).async {
            let page = trackDAO.getAll(limit: Self.pageSize, offset: currentOffset)
            DispatchQueue.main.async {
                tracks.append(contentsOf: page)
                hasLoadedAll = page.count < Self.pageSize
                isLoadingMore = false
            }
        }
    }

    private func refreshChangedTracks(_ notification: Notification) {
        guard let trackIds = notification.userInfo?["trackIds"] as? [Int64] else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let dao = TrackDAO()
            var updated = tracks
            for id in trackIds {
                if let newTrack = dao.getById(id: id),
                   let idx = updated.firstIndex(where: { $0.id == id }) {
                    updated[idx] = newTrack
                }
            }
            DispatchQueue.main.async {
                tracks = updated
            }
        }
    }
}

extension Track: Identifiable {}
