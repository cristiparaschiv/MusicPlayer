import Foundation
import Combine

class QueueManager: ObservableObject {
    static let shared = QueueManager()

    // MARK: - State (protected by queueLock)

    private var _queue: [Track] = []
    private var _currentIndex: Int = -1
    private var _originalQueue: [Track] = []
    private static let maxShuffleHistory = 100
    private var shuffleHistory: [Int] = []

    private var _isShuffleEnabled: Bool = false
    private var _repeatMode: RepeatMode = .off

    private let queueLock = NSLock()

    private init() {
        loadPersistedState()
    }

    // MARK: - Published Properties (updated on main thread)

    /// Call after any state mutation under lock to sync published state to main thread.
    private func publishState() {
        let q = _queue
        let idx = _currentIndex
        let shuffle = _isShuffleEnabled
        let rpt = _repeatMode
        let publish = { [weak self] in
            guard let self = self else { return }
            self.objectWillChange.send()
            self._publishedQueue = q
            self._publishedCurrentIndex = idx
            self._publishedIsShuffleEnabled = shuffle
            self._publishedRepeatMode = rpt
        }
        if Thread.isMainThread {
            publish()
        } else {
            DispatchQueue.main.async(execute: publish)
        }
    }

    @Published private(set) var _publishedQueue: [Track] = []
    @Published private(set) var _publishedCurrentIndex: Int = -1
    @Published private(set) var _publishedIsShuffleEnabled: Bool = false
    @Published private(set) var _publishedRepeatMode: RepeatMode = .off

    // MARK: - Public Properties (thread-safe reads)

    var currentTrack: Track? {
        queueLock.lock()
        defer { queueLock.unlock() }
        guard _currentIndex >= 0 && _currentIndex < _queue.count else { return nil }
        return _queue[_currentIndex]
    }

    var currentQueue: [Track] {
        queueLock.lock()
        defer { queueLock.unlock() }
        return _queue
    }

    var currentTrackIndex: Int {
        queueLock.lock()
        defer { queueLock.unlock() }
        return _currentIndex
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
        return _queue.count
    }

    var isEmpty: Bool {
        queueLock.lock()
        defer { queueLock.unlock() }
        return _queue.isEmpty
    }

    var hasNext: Bool {
        queueLock.lock()
        defer { queueLock.unlock() }
        if _repeatMode == .one { return true }
        if _repeatMode == .all && !_queue.isEmpty { return true }
        return _currentIndex < _queue.count - 1
    }

    var hasPrevious: Bool {
        queueLock.lock()
        defer { queueLock.unlock() }
        if _repeatMode == .one { return true }
        if _isShuffleEnabled && !shuffleHistory.isEmpty { return true }
        return _currentIndex > 0
    }

    // MARK: - Queue Management

    func setQueue(_ tracks: [Track], startIndex: Int = 0) {
        queueLock.lock()
        _queue = tracks
        _currentIndex = min(max(0, startIndex), tracks.count - 1)
        _originalQueue = tracks
        shuffleHistory = []

        if _isShuffleEnabled && !tracks.isEmpty {
            applyShuffleKeepingCurrentTrack()
        }
        queueLock.unlock()

        publishState()
        debouncePersist()
        notifyQueueChanged()
        notifyCurrentTrackChanged()
    }

    func addToQueue(_ tracks: [Track]) {
        queueLock.lock()

        if _isShuffleEnabled {
            _originalQueue.append(contentsOf: tracks)
            var shuffled = tracks
            shuffled.shuffle()
            _queue.append(contentsOf: shuffled)
        } else {
            _queue.append(contentsOf: tracks)
            _originalQueue.append(contentsOf: tracks)
        }

        if _currentIndex == -1 && !_queue.isEmpty {
            _currentIndex = 0
        }

        let shouldNotifyTrack = _currentIndex == 0 && !tracks.isEmpty
        queueLock.unlock()

        publishState()
        debouncePersist()
        notifyQueueChanged()

        if shouldNotifyTrack {
            notifyCurrentTrackChanged()
        }
    }

    func insertNext(_ tracks: [Track]) {
        queueLock.lock()

        let insertIndex = _currentIndex + 1

        if _isShuffleEnabled {
            _originalQueue.append(contentsOf: tracks)
            if insertIndex <= _queue.count {
                _queue.insert(contentsOf: tracks, at: insertIndex)
            } else {
                _queue.append(contentsOf: tracks)
            }
        } else {
            if insertIndex <= _queue.count {
                _queue.insert(contentsOf: tracks, at: insertIndex)
                _originalQueue.insert(contentsOf: tracks, at: insertIndex)
            } else {
                _queue.append(contentsOf: tracks)
                _originalQueue.append(contentsOf: tracks)
            }
        }

        queueLock.unlock()

        publishState()
        debouncePersist()
        notifyQueueChanged()
    }

    func removeTrack(at index: Int) {
        queueLock.lock()

        guard index >= 0 && index < _queue.count else {
            queueLock.unlock()
            return
        }

        let wasCurrentTrack = (index == _currentIndex)

        let removedTrack = _queue[index]
        if let originalIndex = _originalQueue.firstIndex(where: { $0.id == removedTrack.id }) {
            _originalQueue.remove(at: originalIndex)
        }

        _queue.remove(at: index)

        if index < _currentIndex {
            _currentIndex -= 1
        } else if wasCurrentTrack {
            if _currentIndex >= _queue.count {
                _currentIndex = _queue.count - 1
            }
        }

        if _queue.isEmpty {
            _currentIndex = -1
            _originalQueue = []
            shuffleHistory = []
        }

        queueLock.unlock()

        publishState()
        debouncePersist()
        notifyQueueChanged()

        if wasCurrentTrack {
            notifyCurrentTrackChanged()
        }
    }

    func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        queueLock.lock()

        guard sourceIndex >= 0 && sourceIndex < _queue.count &&
              destinationIndex >= 0 && destinationIndex < _queue.count &&
              sourceIndex != destinationIndex else {
            queueLock.unlock()
            return
        }

        let track = _queue.remove(at: sourceIndex)
        _queue.insert(track, at: destinationIndex)

        if sourceIndex == _currentIndex {
            _currentIndex = destinationIndex
        } else if sourceIndex < _currentIndex && destinationIndex >= _currentIndex {
            _currentIndex -= 1
        } else if sourceIndex > _currentIndex && destinationIndex <= _currentIndex {
            _currentIndex += 1
        }

        queueLock.unlock()

        publishState()
        debouncePersist()
        notifyQueueChanged()
    }

    func clearQueue() {
        queueLock.lock()
        _queue = []
        _currentIndex = -1
        _originalQueue = []
        shuffleHistory = []
        queueLock.unlock()

        publishState()
        debouncePersist()
        notifyQueueChanged()
        notifyCurrentTrackChanged()
    }

    // MARK: - Navigation

    func peekNext() -> Track? {
        queueLock.lock()
        defer { queueLock.unlock() }

        if _repeatMode == .one, _currentIndex >= 0, _currentIndex < _queue.count {
            return _queue[_currentIndex]
        }

        let nextIndex = _currentIndex + 1
        if nextIndex < _queue.count { return _queue[nextIndex] }
        if _repeatMode == .all && !_queue.isEmpty { return _queue[0] }
        return nil
    }

    func next() -> Track? {
        queueLock.lock()

        if _repeatMode == .one {
            let track = (_currentIndex >= 0 && _currentIndex < _queue.count) ? _queue[_currentIndex] : nil
            queueLock.unlock()
            publishState()
            notifyCurrentTrackChanged()
            return track
        }

        let nextIndex = _currentIndex + 1

        if nextIndex < _queue.count {
            _currentIndex = nextIndex
            if _isShuffleEnabled {
                shuffleHistory.append(_currentIndex)
                if shuffleHistory.count > Self.maxShuffleHistory {
                    shuffleHistory.removeFirst(shuffleHistory.count - Self.maxShuffleHistory)
                }
            }
            let track = _queue[_currentIndex]
            queueLock.unlock()

            publishState()
            debouncePersist()
            notifyCurrentTrackChanged()
            return track
        }

        if _repeatMode == .all && !_queue.isEmpty {
            _currentIndex = 0
            if _isShuffleEnabled { shuffleHistory = [0] }
            let track = _queue[0]
            queueLock.unlock()

            publishState()
            debouncePersist()
            notifyCurrentTrackChanged()
            return track
        }

        queueLock.unlock()
        return nil
    }

    func previous() -> Track? {
        queueLock.lock()

        if _repeatMode == .one {
            let track = (_currentIndex >= 0 && _currentIndex < _queue.count) ? _queue[_currentIndex] : nil
            queueLock.unlock()
            publishState()
            notifyCurrentTrackChanged()
            return track
        }

        if _isShuffleEnabled && shuffleHistory.count > 1 {
            shuffleHistory.removeLast()
            _currentIndex = shuffleHistory.last ?? 0
            let track = _queue[_currentIndex]
            queueLock.unlock()

            publishState()
            debouncePersist()
            notifyCurrentTrackChanged()
            return track
        }

        let previousIndex = _currentIndex - 1

        if previousIndex >= 0 {
            _currentIndex = previousIndex
            let track = _queue[_currentIndex]
            queueLock.unlock()

            publishState()
            debouncePersist()
            notifyCurrentTrackChanged()
            return track
        }

        if _repeatMode == .all && !_queue.isEmpty {
            _currentIndex = _queue.count - 1
            let track = _queue[_currentIndex]
            queueLock.unlock()

            publishState()
            debouncePersist()
            notifyCurrentTrackChanged()
            return track
        }

        queueLock.unlock()
        return nil
    }

    func skipToTrack(at index: Int) -> Track? {
        queueLock.lock()

        guard index >= 0 && index < _queue.count else {
            queueLock.unlock()
            return nil
        }

        _currentIndex = index

        if _isShuffleEnabled {
            shuffleHistory.append(index)
            if shuffleHistory.count > Self.maxShuffleHistory {
                shuffleHistory.removeFirst(shuffleHistory.count - Self.maxShuffleHistory)
            }
        }

        let track = _queue[index]
        queueLock.unlock()

        publishState()
        debouncePersist()
        notifyCurrentTrackChanged()
        return track
    }

    // MARK: - Shuffle & Repeat

    func toggleShuffle() {
        setShuffleEnabled(!isShuffleEnabled)
    }

    func setShuffleEnabled(_ enabled: Bool) {
        queueLock.lock()

        guard _isShuffleEnabled != enabled else {
            queueLock.unlock()
            return
        }

        _isShuffleEnabled = enabled

        if enabled {
            if !_queue.isEmpty {
                applyShuffleKeepingCurrentTrack()
            }
        } else {
            if !_originalQueue.isEmpty {
                let currentTrackObj = (_currentIndex >= 0 && _currentIndex < _queue.count)
                    ? _queue[_currentIndex]
                    : nil

                _queue = _originalQueue

                if let track = currentTrackObj,
                   let newIndex = _queue.firstIndex(where: { $0.id == track.id }) {
                    _currentIndex = newIndex
                } else {
                    _currentIndex = 0
                }
            }
            shuffleHistory = []
        }

        queueLock.unlock()

        publishState()
        debouncePersist()
        notifyQueueChanged()
        notifyCurrentTrackChanged()
        notifyShuffleModeChanged()
    }

    func setRepeatMode(_ mode: RepeatMode) {
        queueLock.lock()
        _repeatMode = mode
        queueLock.unlock()

        publishState()
        debouncePersist()

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Constants.Notifications.repeatModeChanged,
                object: nil,
                userInfo: ["repeatMode": mode.rawValue]
            )
        }
    }

    func cycleRepeatMode() {
        let currentMode = repeatMode
        let nextMode: RepeatMode
        switch currentMode {
        case .off: nextMode = .all
        case .all: nextMode = .one
        case .one: nextMode = .off
        }
        setRepeatMode(nextMode)
    }

    // MARK: - Utility Methods

    func indexOfTrack(_ track: Track) -> Int? {
        queueLock.lock()
        defer { queueLock.unlock() }
        return _queue.firstIndex(where: { $0.id == track.id })
    }

    func containsTrack(_ track: Track) -> Bool {
        return indexOfTrack(track) != nil
    }

    func remainingTracks() -> [Track] {
        queueLock.lock()
        defer { queueLock.unlock() }
        guard _currentIndex >= 0 && _currentIndex < _queue.count else { return [] }
        return Array(_queue[_currentIndex...])
    }

    func upcomingTracks(limit: Int? = nil) -> [Track] {
        queueLock.lock()
        defer { queueLock.unlock() }
        let startIndex = _currentIndex + 1
        guard startIndex < _queue.count else { return [] }
        if let limit = limit {
            let endIndex = min(startIndex + limit, _queue.count)
            return Array(_queue[startIndex..<endIndex])
        }
        return Array(_queue[startIndex...])
    }

    // MARK: - Private Methods

    private func applyShuffleKeepingCurrentTrack() {
        // Must be called within lock
        guard !_queue.isEmpty else { return }

        let currentTrackObj = (_currentIndex >= 0 && _currentIndex < _queue.count)
            ? _queue[_currentIndex]
            : nil

        _queue.shuffle()

        if let track = currentTrackObj,
           let shuffledIndex = _queue.firstIndex(where: { $0.id == track.id }) {
            _queue.swapAt(0, shuffledIndex)
            _currentIndex = 0
            shuffleHistory = [0]
        } else {
            _currentIndex = 0
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
        queueLock.lock()
        let index = _currentIndex
        queueLock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Constants.Notifications.trackDidChange,
                object: nil,
                userInfo: ["trackIndex": index]
            )
        }
    }

    private func notifyShuffleModeChanged() {
        queueLock.lock()
        let shuffleEnabled = _isShuffleEnabled
        queueLock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Constants.Notifications.shuffleModeChanged,
                object: nil,
                userInfo: ["shuffleEnabled": shuffleEnabled]
            )
        }
    }

    // MARK: - Persistence

    private var persistWorkItem: DispatchWorkItem?

    private func debouncePersist() {
        persistWorkItem?.cancel()

        queueLock.lock()
        let shuffle = _isShuffleEnabled
        let repeatRaw = _repeatMode.rawValue
        let trackIDs = _queue.map { $0.id }
        let index = _currentIndex
        queueLock.unlock()

        let item = DispatchWorkItem {
            UserDefaults.standard.set(shuffle, forKey: Constants.UserDefaultsKeys.shuffleEnabled)
            UserDefaults.standard.set(repeatRaw, forKey: Constants.UserDefaultsKeys.repeatMode)
            UserDefaults.standard.set(trackIDs, forKey: Constants.UserDefaultsKeys.queueTrackIDs)
            UserDefaults.standard.set(index, forKey: Constants.UserDefaultsKeys.queueCurrentIndex)
        }
        persistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func loadPersistedState() {
        _isShuffleEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.shuffleEnabled)

        if let repeatValue = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.repeatMode),
           let mode = RepeatMode(rawValue: repeatValue) {
            _repeatMode = mode
        }

        if let savedIDs = UserDefaults.standard.array(forKey: Constants.UserDefaultsKeys.queueTrackIDs) as? [Int64],
           !savedIDs.isEmpty {
            let trackDAO = TrackDAO()
            let restoredTracks = savedIDs.compactMap { trackDAO.getById(id: $0) }
            if !restoredTracks.isEmpty {
                _queue = restoredTracks
                _originalQueue = restoredTracks
                _currentIndex = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKeys.queueCurrentIndex)
                if _currentIndex < 0 || _currentIndex >= _queue.count {
                    _currentIndex = 0
                }

                // Sync published state
                _publishedQueue = _queue
                _publishedCurrentIndex = _currentIndex
                _publishedIsShuffleEnabled = _isShuffleEnabled
                _publishedRepeatMode = _repeatMode

                notifyQueueChanged()
                notifyCurrentTrackChanged()
            }
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
        case .off: return "Off"
        case .one: return "Repeat One"
        case .all: return "Repeat All"
        }
    }
}
