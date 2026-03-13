import SwiftUI

struct RecentlyAddedView: View {
    @State private var tracks: [Track] = []
    @State private var tracksToEdit: [Track]?
    @State private var isLoading = true
    @State private var timeWindow: RecentTimeWindow = .all

    private let trackDAO = TrackDAO()

    enum RecentTimeWindow: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
        case twoMonths = "60 Days"
        case threeMonths = "90 Days"
        case all = "All Time"

        var daysAgo: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .twoMonths: return 60
            case .threeMonths: return 90
            case .all: return nil
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recently Added")
                    .font(.largeTitle)
                    .bold()

                Spacer()

                Button(action: playAll) {
                    Label("Play All", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(tracks.isEmpty)

                Button(action: shuffleAll) {
                    Label("Shuffle All", systemImage: "shuffle")
                }
                .buttonStyle(.bordered)
                .disabled(tracks.isEmpty)

                Picker("Period", selection: $timeWindow) {
                    ForEach(RecentTimeWindow.allCases, id: \.self) { window in
                        Text(window.rawValue).tag(window)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Text("\(tracks.count) tracks")
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("No Recently Added Tracks")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text("Tracks added to your library will appear here")
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
                }
            )
        }
        .onAppear { loadTracks() }
        .onChange(of: timeWindow) { _, _ in loadTracks() }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
            loadTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.trackFavoriteChanged)) { _ in
            loadTracks()
        }
        .sheet(isPresented: Binding(get: { tracksToEdit != nil }, set: { if !$0 { tracksToEdit = nil } })) {
            if let tracks = tracksToEdit {
                TrackEditorView(tracks: tracks)
            }
        }
    }

    private func loadTracks() {
        isLoading = true
        let window = timeWindow
        DispatchQueue.global(qos: .userInitiated).async {
            var loaded = trackDAO.getAll(orderBy: .dateAddedDesc)
            if let daysAgo = window.daysAgo {
                let cutoff = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
                loaded = loaded.filter { $0.dateAdded >= cutoff }
            }
            DispatchQueue.main.async {
                tracks = loaded
                isLoading = false
            }
        }
    }

    private func playAll() {
        guard !tracks.isEmpty else { return }
        QueueManager.shared.setQueue(tracks, startIndex: 0)
        PlayerManager.shared.play(track: tracks[0])
    }

    private func shuffleAll() {
        guard !tracks.isEmpty else { return }
        var shuffled = tracks
        shuffled.shuffle()
        QueueManager.shared.setQueue(shuffled, startIndex: 0)
        QueueManager.shared.setShuffleEnabled(true)
        PlayerManager.shared.play(track: shuffled[0])
    }
}
