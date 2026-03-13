import Foundation
import Combine

class RadioManager: ObservableObject {
    static let shared = RadioManager()

    @Published private(set) var activeStation: RadioStation?
    @Published private(set) var isActive: Bool = false

    private var usedTrackIds = Set<Int64>()
    private var isExpanding = false
    private var trackObserver: NSObjectProtocol?
    private var queueObserver: NSObjectProtocol?
    private let trackDAO = TrackDAO()

    private let initialBatchSize = 20
    private let expansionBatchSize = 10
    private let expansionThreshold = 5

    private init() {}

    // MARK: - Public API

    func startStation(_ station: RadioStation) {
        stop()

        let tracks = trackDAO.getRandomTracksByGenreKeywords(
            station.keywords, limit: initialBatchSize, excluding: usedTrackIds,
            excludingKeywords: station.excludedKeywords
        )

        guard !tracks.isEmpty else { return }

        activeStation = station
        isActive = true
        usedTrackIds = Set(tracks.map { $0.id })

        QueueManager.shared.setQueue(tracks, startIndex: 0)
        PlayerManager.shared.play(track: tracks[0])

        startMonitoring()
        NotificationCenter.default.post(name: Constants.Notifications.radioStateChanged, object: nil)
    }

    func stop() {
        stopMonitoring()
        activeStation = nil
        isActive = false
        usedTrackIds.removeAll()
        NotificationCenter.default.post(name: Constants.Notifications.radioStateChanged, object: nil)
    }

    // MARK: - Queue Monitoring

    private func startMonitoring() {
        trackObserver = NotificationCenter.default.addObserver(
            forName: Constants.Notifications.trackDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkAndExpand()
        }

        queueObserver = NotificationCenter.default.addObserver(
            forName: Constants.Notifications.queueDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isActive, !self.isExpanding else { return }
            let currentQueue = QueueManager.shared.currentQueue
            let currentIds = Set(currentQueue.map { $0.id })
            if !currentIds.isSubset(of: self.usedTrackIds) {
                self.stop()
            }
        }
    }

    private func stopMonitoring() {
        if let observer = trackObserver {
            NotificationCenter.default.removeObserver(observer)
            trackObserver = nil
        }
        if let observer = queueObserver {
            NotificationCenter.default.removeObserver(observer)
            queueObserver = nil
        }
    }

    private func checkAndExpand() {
        guard isActive, let station = activeStation, !isExpanding else { return }

        let queue = QueueManager.shared.currentQueue
        let currentIndex = QueueManager.shared.currentTrackIndex
        let remaining = queue.count - currentIndex - 1

        guard remaining <= expansionThreshold else { return }

        isExpanding = true

        let newTracks = trackDAO.getRandomTracksByGenreKeywords(
            station.keywords, limit: expansionBatchSize, excluding: usedTrackIds,
            excludingKeywords: station.excludedKeywords
        )

        if !newTracks.isEmpty {
            for track in newTracks {
                usedTrackIds.insert(track.id)
            }
            QueueManager.shared.addToQueue(newTracks)
        }

        isExpanding = false
    }
}
