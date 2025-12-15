import Foundation

class QueueManager {
    static let shared = QueueManager()

    // MARK: - State

    private var queue: [Track] = []
    private var currentIndex: Int = -1
    private var originalQueue: [Track] = [] // For shuffle mode
    private var shuffleHistory: [Int] = [] // Track indices we've played in shuffle mode

    private var _isShuffleEnabled: Bool = false
    private var _repeatMode: RepeatMode = .off

    private let queueLock = NSLock()
    private let queueQueue = DispatchQueue(label: "com.orangemusicplayer.queue", qos: .userInitiated)

    private init() {
        loadPersistedState()
    }

    // MARK: - Public Properties

    var currentTrack: Track? {
        queueLock.lock()
        defer { queueLock.unlock() }

        guard currentIndex >= 0 && currentIndex < queue.count else {
            return nil
        }
        return queue[currentIndex]
    }

    var currentQueue: [Track] {
        queueLock.lock()
        defer { queueLock.unlock() }
        return queue
    }

    var currentTrackIndex: Int {
        queueLock.lock()
        defer { queueLock.unlock() }
        return currentIndex
    }

    var isShuffleEnabled: Bool {
        queueLock.lock()
        defer { queueLock.unlock() }
        return _isShuffleEnabled
    }

    var repeatMode: RepeatMode {
        queueLock.lock()
        defer { queueLock.unlock() }
        return _repeatMode
    }

    var queueCount: Int {
        queueLock.lock()
        defer { queueLock.unlock() }
        return queue.count
    }

    var isEmpty: Bool {
        queueLock.lock()
        defer { queueLock.unlock() }
        return queue.isEmpty
    }

    var hasNext: Bool {
        queueLock.lock()
        defer { queueLock.unlock() }

        if _repeatMode == .one {
            return true
        }

        if _repeatMode == .all && !queue.isEmpty {
            return true
        }

        return currentIndex < queue.count - 1
    }

    var hasPrevious: Bool {
        queueLock.lock()
        defer { queueLock.unlock() }

        if _repeatMode == .one {
            return true
        }

        if _isShuffleEnabled && !shuffleHistory.isEmpty {
            return true
        }

        return currentIndex > 0
    }

    // MARK: - Queue Management

    /// Set the entire queue and start from a specific track
    func setQueue(_ tracks: [Track], startIndex: Int = 0) {
        queueQueue.async { [weak self] in
            guard let self = self else { return }

            self.queueLock.lock()
            self.queue = tracks
            self.currentIndex = min(max(0, startIndex), tracks.count - 1)
            self.originalQueue = tracks
            self.shuffleHistory = []

            // Apply shuffle if it's enabled
            if self._isShuffleEnabled && !tracks.isEmpty {
                self.applyShuffleKeepingCurrentTrack()
            }
            self.queueLock.unlock()

            self.persistState()
            self.notifyQueueChanged()
            self.notifyCurrentTrackChanged()
        }
    }

    /// Add tracks to the end of the queue
    func addToQueue(_ tracks: [Track]) {
        queueQueue.async { [weak self] in
            guard let self = self else { return }

            self.queueLock.lock()

            if self._isShuffleEnabled {
                // Add to original queue
                self.originalQueue.append(contentsOf: tracks)

                // Shuffle and add to current queue
                var shuffledTracks = tracks
                shuffledTracks.shuffle()
                self.queue.append(contentsOf: shuffledTracks)
            } else {
                self.queue.append(contentsOf: tracks)
                self.originalQueue.append(contentsOf: tracks)
            }

            // If queue was empty, set current index to 0
            if self.currentIndex == -1 && !self.queue.isEmpty {
                self.currentIndex = 0
            }

            self.queueLock.unlock()

            self.persistState()
            self.notifyQueueChanged()

            // Notify current track if we just added the first track
            if self.currentIndex == 0 && tracks.count > 0 {
                self.notifyCurrentTrackChanged()
            }
        }
    }

    /// Insert tracks immediately after the current track (play next)
    func insertNext(_ tracks: [Track]) {
        queueQueue.async { [weak self] in
            guard let self = self else { return }

            self.queueLock.lock()

            let insertIndex = self.currentIndex + 1

            if self._isShuffleEnabled {
                // Insert into original queue at the end
                self.originalQueue.append(contentsOf: tracks)

                // Insert into shuffled queue right after current
                if insertIndex <= self.queue.count {
                    self.queue.insert(contentsOf: tracks, at: insertIndex)
                } else {
                    self.queue.append(contentsOf: tracks)
                }
            } else {
                if insertIndex <= self.queue.count {
                    self.queue.insert(contentsOf: tracks, at: insertIndex)
                    self.originalQueue.insert(contentsOf: tracks, at: insertIndex)
                } else {
                    self.queue.append(contentsOf: tracks)
                    self.originalQueue.append(contentsOf: tracks)
                }
            }

            self.queueLock.unlock()

            self.persistState()
            self.notifyQueueChanged()
        }
    }

    /// Remove a track from the queue
    func removeTrack(at index: Int) {
        queueQueue.async { [weak self] in
            guard let self = self else { return }

            self.queueLock.lock()

            guard index >= 0 && index < self.queue.count else {
                self.queueLock.unlock()
                return
            }

            self.queue.remove(at: index)

            // Adjust current index if needed
            if index < self.currentIndex {
                self.currentIndex -= 1
            } else if index == self.currentIndex {
                // Removed current track, stay at same index (which is now the next track)
                if self.currentIndex >= self.queue.count {
                    self.currentIndex = self.queue.count - 1
                }
            }

            // Clean up if queue is empty
            if self.queue.isEmpty {
                self.currentIndex = -1
                self.originalQueue = []
                self.shuffleHistory = []
            }

            self.queueLock.unlock()

            self.persistState()
            self.notifyQueueChanged()

            if index == self.currentIndex {
                self.notifyCurrentTrackChanged()
            }
        }
    }

    /// Move a track from one position to another
    func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        queueQueue.async { [weak self] in
            guard let self = self else { return }

            self.queueLock.lock()

            guard sourceIndex >= 0 && sourceIndex < self.queue.count &&
                  destinationIndex >= 0 && destinationIndex < self.queue.count &&
                  sourceIndex != destinationIndex else {
                self.queueLock.unlock()
                return
            }

            let track = self.queue.remove(at: sourceIndex)
            self.queue.insert(track, at: destinationIndex)

            // Adjust current index
            if sourceIndex == self.currentIndex {
                self.currentIndex = destinationIndex
            } else if sourceIndex < self.currentIndex && destinationIndex >= self.currentIndex {
                self.currentIndex -= 1
            } else if sourceIndex > self.currentIndex && destinationIndex <= self.currentIndex {
                self.currentIndex += 1
            }

            self.queueLock.unlock()

            self.persistState()
            self.notifyQueueChanged()
        }
    }

    /// Clear the entire queue
    func clearQueue() {
        queueQueue.async { [weak self] in
            guard let self = self else { return }

            self.queueLock.lock()
            self.queue = []
            self.currentIndex = -1
            self.originalQueue = []
            self.shuffleHistory = []
            self.queueLock.unlock()

            self.persistState()
            self.notifyQueueChanged()
            self.notifyCurrentTrackChanged()
        }
    }

    // MARK: - Navigation

    /// Get the next track without advancing the queue
    func peekNext() -> Track? {
        queueLock.lock()
        defer { queueLock.unlock() }

        if _repeatMode == .one, let current = currentTrack {
            return current
        }

        let nextIndex = currentIndex + 1

        if nextIndex < queue.count {
            return queue[nextIndex]
        }

        if _repeatMode == .all && !queue.isEmpty {
            return queue[0]
        }

        return nil
    }

    /// Advance to the next track
    func next() -> Track? {
        queueLock.lock()

        if _repeatMode == .one {
            let track = currentTrack
            queueLock.unlock()
            notifyCurrentTrackChanged()
            return track
        }

        let nextIndex = currentIndex + 1

        if nextIndex < queue.count {
            currentIndex = nextIndex
            if _isShuffleEnabled {
                shuffleHistory.append(currentIndex)
            }
            let track = queue[currentIndex]
            queueLock.unlock()

            persistState()
            notifyCurrentTrackChanged()
            return track
        }

        if _repeatMode == .all && !queue.isEmpty {
            currentIndex = 0
            if _isShuffleEnabled {
                shuffleHistory = [0]
            }
            let track = queue[0]
            queueLock.unlock()

            persistState()
            notifyCurrentTrackChanged()
            return track
        }

        queueLock.unlock()
        return nil
    }

    /// Go to the previous track
    func previous() -> Track? {
        queueLock.lock()

        if _repeatMode == .one {
            let track = currentTrack
            queueLock.unlock()
            notifyCurrentTrackChanged()
            return track
        }

        if _isShuffleEnabled && shuffleHistory.count > 1 {
            // Remove current from history and go to previous
            shuffleHistory.removeLast()
            currentIndex = shuffleHistory.last ?? 0
            let track = queue[currentIndex]
            queueLock.unlock()

            persistState()
            notifyCurrentTrackChanged()
            return track
        }

        let previousIndex = currentIndex - 1

        if previousIndex >= 0 {
            currentIndex = previousIndex
            let track = queue[currentIndex]
            queueLock.unlock()

            persistState()
            notifyCurrentTrackChanged()
            return track
        }

        if _repeatMode == .all && !queue.isEmpty {
            currentIndex = queue.count - 1
            let track = queue[currentIndex]
            queueLock.unlock()

            persistState()
            notifyCurrentTrackChanged()
            return track
        }

        queueLock.unlock()
        return nil
    }

    /// Jump to a specific track in the queue
    func skipToTrack(at index: Int) -> Track? {
        queueLock.lock()

        guard index >= 0 && index < queue.count else {
            queueLock.unlock()
            return nil
        }

        currentIndex = index

        if _isShuffleEnabled {
            shuffleHistory.append(index)
        }

        let track = queue[index]
        queueLock.unlock()

        persistState()
        notifyCurrentTrackChanged()
        return track
    }

    // MARK: - Shuffle & Repeat

    /// Toggle shuffle mode
    func toggleShuffle() {
        setShuffleEnabled(!isShuffleEnabled)
    }

    /// Set shuffle mode
    func setShuffleEnabled(_ enabled: Bool) {
        queueQueue.async { [weak self] in
            guard let self = self else { return }

            self.queueLock.lock()

            guard self._isShuffleEnabled != enabled else {
                self.queueLock.unlock()
                return
            }

            self._isShuffleEnabled = enabled

            if enabled {
                // Enabling shuffle
                if !self.queue.isEmpty {
                    self.applyShuffleKeepingCurrentTrack()
                }
            } else {
                // Disabling shuffle - restore original queue
                if !self.originalQueue.isEmpty {
                    let currentTrack = self.queue.count > self.currentIndex && self.currentIndex >= 0
                        ? self.queue[self.currentIndex]
                        : nil

                    self.queue = self.originalQueue

                    // Find current track in original queue
                    if let track = currentTrack,
                       let newIndex = self.queue.firstIndex(where: { $0.id == track.id }) {
                        self.currentIndex = newIndex
                    } else {
                        self.currentIndex = 0
                    }
                }
                self.shuffleHistory = []
            }

            self.queueLock.unlock()

            self.persistState()
            self.notifyQueueChanged()
            self.notifyCurrentTrackChanged()
            self.notifyShuffleModeChanged()
        }
    }

    /// Set repeat mode
    func setRepeatMode(_ mode: RepeatMode) {
        queueQueue.async { [weak self] in
            guard let self = self else { return }

            self.queueLock.lock()
            self._repeatMode = mode
            self.queueLock.unlock()

            self.persistState()

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.repeatModeChanged,
                    object: nil,
                    userInfo: ["repeatMode": mode.rawValue]
                )
            }
        }
    }

    /// Cycle through repeat modes (off -> all -> one -> off)
    func cycleRepeatMode() {
        let currentMode = repeatMode
        let nextMode: RepeatMode

        switch currentMode {
        case .off:
            nextMode = .all
        case .all:
            nextMode = .one
        case .one:
            nextMode = .off
        }

        setRepeatMode(nextMode)
    }

    // MARK: - Utility Methods

    /// Get the index of a track in the queue
    func indexOfTrack(_ track: Track) -> Int? {
        queueLock.lock()
        defer { queueLock.unlock() }

        return queue.firstIndex(where: { $0.id == track.id })
    }

    /// Check if a track is in the queue
    func containsTrack(_ track: Track) -> Bool {
        return indexOfTrack(track) != nil
    }

    /// Get tracks remaining in queue (from current position onwards)
    func remainingTracks() -> [Track] {
        queueLock.lock()
        defer { queueLock.unlock() }

        guard currentIndex >= 0 && currentIndex < queue.count else {
            return []
        }

        return Array(queue[currentIndex...])
    }

    /// Get upcoming tracks (excluding current)
    func upcomingTracks(limit: Int? = nil) -> [Track] {
        queueLock.lock()
        defer { queueLock.unlock() }

        let startIndex = currentIndex + 1

        guard startIndex < queue.count else {
            return []
        }

        if let limit = limit {
            let endIndex = min(startIndex + limit, queue.count)
            return Array(queue[startIndex..<endIndex])
        }

        return Array(queue[startIndex...])
    }

    // MARK: - Private Methods

    private func applyShuffleKeepingCurrentTrack() {
        // Must be called within lock
        guard !queue.isEmpty else { return }

        let currentTrack = currentIndex >= 0 && currentIndex < queue.count
            ? queue[currentIndex]
            : nil

        // Shuffle the queue
        queue.shuffle()

        // Move current track to the front if it exists
        if let track = currentTrack,
           let shuffledIndex = queue.firstIndex(where: { $0.id == track.id }) {
            queue.swapAt(0, shuffledIndex)
            currentIndex = 0
            shuffleHistory = [0]
        } else {
            currentIndex = 0
            shuffleHistory = [0]
        }
    }

    private func notifyQueueChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Constants.Notifications.queueDidChange,
                object: nil
            )
        }
    }

    private func notifyCurrentTrackChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Constants.Notifications.trackDidChange,
                object: nil,
                userInfo: ["trackIndex": self.currentIndex]
            )
        }
    }

    private func notifyShuffleModeChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Constants.Notifications.shuffleModeChanged,
                object: nil,
                userInfo: ["shuffleEnabled": self._isShuffleEnabled]
            )
        }
    }

    // MARK: - Persistence

    private func persistState() {
        UserDefaults.standard.set(_isShuffleEnabled, forKey: Constants.UserDefaultsKeys.shuffleEnabled)
        UserDefaults.standard.set(_repeatMode.rawValue, forKey: Constants.UserDefaultsKeys.repeatMode)
    }

    private func loadPersistedState() {
        _isShuffleEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.shuffleEnabled)

        if let repeatValue = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.repeatMode),
           let mode = RepeatMode(rawValue: repeatValue) {
            _repeatMode = mode
        }
    }
}

// MARK: - Supporting Types

enum RepeatMode: String, Codable {
    case off
    case one
    case all

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .one:
            return "Repeat One"
        case .all:
            return "Repeat All"
        }
    }
}
