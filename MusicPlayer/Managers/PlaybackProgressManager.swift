import Foundation
import Combine

@MainActor
class PlaybackProgressManager: ObservableObject {
    static let shared = PlaybackProgressManager()

    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private init() {
        setupNotificationObservers()
        loadInitialState()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackTimeChanged(_:)),
            name: Constants.Notifications.playbackTimeChanged,
            object: nil
        )
    }

    @objc private func handlePlaybackTimeChanged(_ notification: Notification) {
        currentTime = PlayerManager.shared.currentTime
        duration = PlayerManager.shared.duration
    }

    private func loadInitialState() {
        currentTime = PlayerManager.shared.currentTime
        duration = PlayerManager.shared.duration
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
