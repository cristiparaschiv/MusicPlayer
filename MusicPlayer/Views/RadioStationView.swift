import SwiftUI

struct RadioStationView: View {
    let station: RadioStation
    @ObservedObject private var radioManager = RadioManager.shared
    @State private var previewTracks: [Track] = []
    @State private var trackCount: Int = 0
    @State private var queueSnapshot: [Track] = []
    @State private var tracksToEdit: [Track]?

    private let trackDAO = TrackDAO()

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            if radioManager.activeStation == station && radioManager.isActive {
                TrackTableView(
                    tracks: queueSnapshot,
                    config: TrackTableConfig(onEditTrack: { tracksToEdit = $0 }),
                    onPlayTrack: { track, allTracks in
                        if let index = allTracks.firstIndex(where: { $0.id == track.id }) {
                            _ = QueueManager.shared.skipToTrack(at: index)
                            PlayerManager.shared.play(track: track)
                        }
                    }
                )
            } else {
                TrackTableView(
                    tracks: previewTracks,
                    config: TrackTableConfig(onEditTrack: { tracksToEdit = $0 }),
                    onPlayTrack: { _, _ in
                        radioManager.startStation(station)
                    }
                )
            }
        }
        .onAppear {
            loadPreview()
            updateQueueSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.queueDidChange)) { _ in
            updateQueueSnapshot()
        }
        .sheet(isPresented: Binding(get: { tracksToEdit != nil }, set: { if !$0 { tracksToEdit = nil } })) {
            if let tracks = tracksToEdit {
                TrackEditorView(tracks: tracks)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.trackMetadataChanged)) { _ in
            loadPreview()
            updateQueueSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.radioStateChanged)) { _ in
            if !(radioManager.activeStation == station && radioManager.isActive) {
                loadPreview()
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.8), .accentColor.opacity(0.4)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: station.icon)
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            .shadow(color: .accentColor.opacity(0.3), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 10) {
                Text(station.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("\(trackCount) tracks available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    if radioManager.activeStation == station && radioManager.isActive {
                        Button(action: { radioManager.stop() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 14))
                                Text("Stop Radio")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button(action: { radioManager.startStation(station) }) {
                            HStack(spacing: 6) {
                                Image(systemName: Icons.playFill)
                                    .font(.system(size: 14))
                                Text("Start Radio")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(16)
    }

    private func loadPreview() {
        trackCount = trackDAO.countTracksByGenreKeywords(station.keywords, excludingKeywords: station.excludedKeywords)
        previewTracks = trackDAO.getRandomTracksByGenreKeywords(station.keywords, limit: 20, excludingKeywords: station.excludedKeywords)
    }

    private func updateQueueSnapshot() {
        if radioManager.activeStation == station && radioManager.isActive {
            queueSnapshot = QueueManager.shared.currentQueue
        }
    }
}
