import Foundation
import SFBAudioEngine
import AVFoundation

class PlayerManager {
    static let shared = PlayerManager()

    // MARK: - Audio Engine

    private var audioPlayer: AudioPlayer?
    private var nextAudioPlayer: AudioPlayer? // For gapless playback

    // MARK: - State

    private var _playbackState: PlaybackState = .stopped
    private var _currentTrack: Track?
    private var _volume: Float = Constants.defaultVolume
    private var _isCrossfadeEnabled: Bool = false
    private var _crossfadeDuration: TimeInterval = Constants.defaultCrossfadeDuration
    private var _isGaplessEnabled: Bool = true

    private let stateLock = NSLock()
    private let playerQueue = DispatchQueue(label: "com.orangemusicplayer.player", qos: .userInitiated)

    private var playbackTimer: Timer?
    private var crossfadeTimer: Timer?

    private let trackDAO = TrackDAO()

    // MARK: - Initialization

    private init() {
        setupAudioSession()
        loadPersistedSettings()
        observeQueueManager()
    }

    // MARK: - Public Properties

    var playbackState: PlaybackState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _playbackState
    }

    var isPlaying: Bool {
        return playbackState == .playing
    }

    var isPaused: Bool {
        return playbackState == .paused
    }

    var isStopped: Bool {
        return playbackState == .stopped
    }

    var currentTrack: Track? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _currentTrack
    }

    var volume: Float {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _volume
        }
        set {
            setVolume(newValue)
        }
    }

    var currentTime: TimeInterval {
        guard let player = audioPlayer, player.isPlaying else {
            return 0
        }
        return player.currentTime ?? 0
    }

    var duration: TimeInterval {
        return currentTrack?.duration ?? 0
    }

    var isCrossfadeEnabled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isCrossfadeEnabled
    }

    var isGaplessEnabled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isGaplessEnabled
    }

    var isShuffleEnabled: Bool {
        return QueueManager.shared.isShuffleEnabled
    }

    var repeatMode: RepeatMode {
        return QueueManager.shared.repeatMode
    }

    // MARK: - Playback Control

    /// Play the current track or resume if paused
    func play() {
        playerQueue.async { [weak self] in
            guard let self = self else { return }

            self.stateLock.lock()

            if self._playbackState == .paused, let player = self.audioPlayer {
                // Resume playback
                do {
                    try player.play()
                    self._playbackState = .playing
                    self.stateLock.unlock()

                    self.notifyPlaybackStateChanged()
                    self.startPlaybackTimer()
                    return
                } catch {
                    print("Failed to resume playback: \(error)")
                    self.stateLock.unlock()
                    return
                }
            }

            // Start new playback
            guard let track = QueueManager.shared.currentTrack else {
                self.stateLock.unlock()
                return
            }

            self._currentTrack = track
            self.stateLock.unlock()

            self.playTrack(track)
        }
    }

    /// Play a specific track
    func play(track: Track) {
        playerQueue.async { [weak self] in
            guard let self = self else { return }

            // Set queue to single track if not already in queue
            if QueueManager.shared.indexOfTrack(track) == nil {
                QueueManager.shared.setQueue([track], startIndex: 0)
            } else {
                // Skip to track in queue
                _ = QueueManager.shared.skipToTrack(at: QueueManager.shared.indexOfTrack(track)!)
            }

            self.stateLock.lock()
            self._currentTrack = track
            self.stateLock.unlock()

            self.playTrack(track)
        }
    }

    /// Pause playback
    func pause() {
        playerQueue.async { [weak self] in
            guard let self = self else { return }

            self.stateLock.lock()

            guard self._playbackState == .playing, let player = self.audioPlayer else {
                self.stateLock.unlock()
                return
            }

            player.pause()
            self._playbackState = .paused
            self.stateLock.unlock()

            self.stopPlaybackTimer()
            self.notifyPlaybackStateChanged()
        }
    }

    /// Stop playback completely
    func stop() {
        playerQueue.async { [weak self] in
            guard let self = self else { return }

            self.stateLock.lock()

            self.audioPlayer?.stop()
            self.audioPlayer = nil
            self.nextAudioPlayer?.stop()
            self.nextAudioPlayer = nil

            self._playbackState = .stopped
            self._currentTrack = nil
            self.stateLock.unlock()

            self.stopPlaybackTimer()
            self.notifyPlaybackStateChanged()
        }
    }

    /// Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Skip to next track
    func next() {
        playerQueue.async { [weak self] in
            guard let self = self else { return }

            guard let nextTrack = QueueManager.shared.next() else {
                self.stop()
                return
            }

            self.stateLock.lock()
            self._currentTrack = nextTrack
            self.stateLock.unlock()

            self.playTrack(nextTrack)
        }
    }

    /// Skip to previous track
    func previous() {
        playerQueue.async { [weak self] in
            guard let self = self else { return }

            // If we're more than 3 seconds into the track, restart it
            if self.currentTime > 3.0 {
                self.seek(to: 0)
                return
            }

            guard let previousTrack = QueueManager.shared.previous() else {
                self.seek(to: 0)
                return
            }

            self.stateLock.lock()
            self._currentTrack = previousTrack
            self.stateLock.unlock()

            self.playTrack(previousTrack)
        }
    }

    // MARK: - Volume Control

    func setVolume(_ volume: Float) {
        let clampedVolume = min(max(0.0, volume), 1.0)

        playerQueue.async { [weak self] in
            guard let self = self else { return }

            self.stateLock.lock()
            self._volume = clampedVolume
            // Note: SFBAudioEngine AudioPlayer doesn't have direct volume control
            // Volume would be controlled through system audio or AVAudioEngine
            self.stateLock.unlock()

            UserDefaults.standard.set(clampedVolume, forKey: Constants.UserDefaultsKeys.volume)

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.volumeChanged,
                    object: nil,
                    userInfo: ["volume": clampedVolume]
                )
            }
        }
    }

    func increaseVolume(by amount: Float = 0.1) {
        setVolume(volume + amount)
    }

    func decreaseVolume(by amount: Float = 0.1) {
        setVolume(volume - amount)
    }

    // MARK: - Seeking

    func seek(to time: TimeInterval) {
        let seekTime = time
        playerQueue.async { [weak self] in
            self?.performSeekOnQueue(seekTime)
        }
    }

    private func performSeekOnQueue(_ time: TimeInterval) {
        guard audioPlayer != nil else { return }

        let duration = self.duration
        let clampedTime = min(max(0.0, time), duration)

        // TODO: Implement seeking with SFBAudioEngine
        // SFBAudioEngine AudioPlayer seeking needs to be properly implemented
        // The AudioPlayer class may need different approach for seeking
        print("Seek to \(clampedTime) requested - seeking functionality to be implemented")

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Constants.Notifications.playbackTimeChanged,
                object: nil,
                userInfo: ["currentTime": clampedTime]
            )
        }
    }

    func seekForward(_ seconds: TimeInterval = 10) {
        seek(to: currentTime + seconds)
    }

    func seekBackward(_ seconds: TimeInterval = 10) {
        seek(to: currentTime - seconds)
    }

    // MARK: - Shuffle & Repeat

    func toggleShuffle() {
        QueueManager.shared.toggleShuffle()
    }

    func setShuffleEnabled(_ enabled: Bool) {
        QueueManager.shared.setShuffleEnabled(enabled)
    }

    func cycleRepeatMode() {
        QueueManager.shared.cycleRepeatMode()
    }

    func setRepeatMode(_ mode: RepeatMode) {
        QueueManager.shared.setRepeatMode(mode)
    }

    // MARK: - Playback Settings

    func setCrossfadeEnabled(_ enabled: Bool) {
        stateLock.lock()
        _isCrossfadeEnabled = enabled
        stateLock.unlock()

        UserDefaults.standard.set(enabled, forKey: Constants.UserDefaultsKeys.crossfadeEnabled)
    }

    func setCrossfadeDuration(_ duration: TimeInterval) {
        stateLock.lock()
        _crossfadeDuration = max(1.0, min(10.0, duration))
        stateLock.unlock()

        UserDefaults.standard.set(_crossfadeDuration, forKey: Constants.UserDefaultsKeys.crossfadeDuration)
    }

    func setGaplessEnabled(_ enabled: Bool) {
        stateLock.lock()
        _isGaplessEnabled = enabled
        stateLock.unlock()

        UserDefaults.standard.set(enabled, forKey: Constants.UserDefaultsKeys.gaplessPlaybackEnabled)
    }

    // MARK: - Favorites

    func toggleFavorite() {
        guard let track = currentTrack else { return }
        toggleFavorite(track: track)
    }

    func toggleFavorite(track: Track) {
        playerQueue.async { [weak self] in
            guard let self = self else { return }

            let newFavoriteState = !track.isFavorite
            self.trackDAO.updateFavorite(trackId: track.id, isFavorite: newFavoriteState)

            // Update current track if it's the one being favorited
            self.stateLock.lock()
            if self._currentTrack?.id == track.id {
                self._currentTrack = self.trackDAO.getById(id: track.id)
            }
            self.stateLock.unlock()

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.trackFavoriteChanged,
                    object: nil,
                    userInfo: ["trackId": track.id, "isFavorite": newFavoriteState]
                )
            }
        }
    }

    func setFavorite(track: Track, isFavorite: Bool) {
        playerQueue.async { [weak self] in
            guard let self = self else { return }

            self.trackDAO.updateFavorite(trackId: track.id, isFavorite: isFavorite)

            // Update current track if it's the one being favorited
            self.stateLock.lock()
            if self._currentTrack?.id == track.id {
                self._currentTrack = self.trackDAO.getById(id: track.id)
            }
            self.stateLock.unlock()

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.trackFavoriteChanged,
                    object: nil,
                    userInfo: ["trackId": track.id, "isFavorite": isFavorite]
                )
            }
        }
    }

    // MARK: - History & Statistics

    func getMostPlayedTracks(limit: Int = 20) -> [Track] {
        return trackDAO.getMostPlayed(limit: limit)
    }

    func getRecentlyPlayedTracks(limit: Int = 20) -> [Track] {
        return trackDAO.getRecentlyPlayed(limit: limit)
    }

    func getMostPlayedArtists(limit: Int = 20) -> [(artist: String, playCount: Int)] {
        let db = DatabaseManager.shared
        let sql = """
            SELECT artist_name, SUM(play_count) as total_plays
            FROM tracks
            WHERE artist_name IS NOT NULL
            GROUP BY artist_name
            ORDER BY total_plays DESC
            LIMIT ?
        """

        let results = db.query(sql: sql, parameters: [limit])
        return results.compactMap { row in
            guard let artist = row["artist_name"] as? String,
                  let playCount = row["total_plays"] as? Int64 else {
                return nil
            }
            return (artist: artist, playCount: Int(playCount))
        }
    }

    func getPlayCountForTrack(_ track: Track) -> Int {
        return trackDAO.getById(id: track.id)?.playCount ?? 0
    }

    // MARK: - Private Methods - Playback

    private func playTrack(_ track: Track) {
        // Must be called from playerQueue

        // Stop any existing playback
        audioPlayer?.stop()
        audioPlayer = nil

        // Create URL for the track
        let url = URL(fileURLWithPath: track.filePath)

        // Try to create audio player
        let player = AudioPlayer()

        do {
            try player.play(url)
            audioPlayer = player
        } catch {
            print("Failed to start playback: \(error)")
            stateLock.lock()
            _playbackState = .stopped
            stateLock.unlock()
            notifyPlaybackStateChanged()
            return
        }

        stateLock.lock()
        _playbackState = .playing
        stateLock.unlock()

        // Update play count after a few seconds (to avoid counting skips)
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self,
                  self._currentTrack?.id == track.id,
                  self.isPlaying else { return }

            self.trackDAO.updatePlayCount(trackId: track.id)
        }

        // Prepare next track for gapless playback
        if _isGaplessEnabled {
            prepareNextTrack()
        }

        // Setup completion handler
        setupPlaybackCompletion()

        notifyPlaybackStateChanged()
        notifyCurrentTrackChanged()
        startPlaybackTimer()
    }

    private func prepareNextTrack() {
        // Must be called from playerQueue
        guard let nextTrack = QueueManager.shared.peekNext() else { return }

        let url = URL(fileURLWithPath: nextTrack.filePath)

        // Try to create next audio player
        let nextPlayer = AudioPlayer()
        do {
            try nextPlayer.play(url)
            nextPlayer.pause()
            nextAudioPlayer = nextPlayer
            print("Prepared next track: \(nextTrack.title)")
        } catch {
            print("Failed to prepare next track: \(error)")
        }
    }

    private func setupPlaybackCompletion() {
        // Use a timer to check for completion
        // SFBAudioEngine doesn't have a direct completion callback in the same way
        // We'll need to monitor the playback state
        playerQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkPlaybackCompletion()
        }
    }

    private func checkPlaybackCompletion() {
        guard let player = audioPlayer else { return }

        if !player.isPlaying && _playbackState == .playing {
            // Playback completed
            handleTrackCompletion()
        } else if _playbackState == .playing {
            // Still playing, check again
            playerQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.checkPlaybackCompletion()
            }
        }
    }

    private func handleTrackCompletion() {
        // Track finished playing, move to next
        if QueueManager.shared.hasNext {
            next()
        } else {
            stop()
        }
    }

    // MARK: - Private Methods - Timers

    private func startPlaybackTimer() {
        stopPlaybackTimer()

        DispatchQueue.main.async { [weak self] in
            self?.playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self, self.isPlaying else { return }

                NotificationCenter.default.post(
                    name: Constants.Notifications.playbackTimeChanged,
                    object: nil,
                    userInfo: ["currentTime": self.currentTime, "duration": self.duration]
                )
            }
        }
    }

    private func stopPlaybackTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.playbackTimer?.invalidate()
            self?.playbackTimer = nil
        }
    }

    // MARK: - Private Methods - Setup

    private func setupAudioSession() {
        // Configure AVAudioSession for macOS
        // Most audio session configuration is automatic on macOS
    }

    private func loadPersistedSettings() {
        _volume = UserDefaults.standard.float(forKey: Constants.UserDefaultsKeys.volume)
        if _volume == 0 {
            _volume = Constants.defaultVolume
        }

        _isCrossfadeEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.crossfadeEnabled)
        _isGaplessEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.gaplessPlaybackEnabled)

        if let duration = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.crossfadeDuration) as? TimeInterval {
            _crossfadeDuration = duration
        }
    }

    private func observeQueueManager() {
        // Observe queue changes to update current track if needed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQueueChanged),
            name: Constants.Notifications.queueDidChange,
            object: nil
        )
    }

    @objc private func handleQueueChanged() {
        validateCurrentTrack()
    }

    private func validateCurrentTrack() {
        stateLock.lock()
        defer { stateLock.unlock() }

        if let current = _currentTrack,
           QueueManager.shared.indexOfTrack(current) == nil {
            // Current track no longer in queue
            _currentTrack = QueueManager.shared.currentTrack
            notifyCurrentTrackChanged()
        }
    }

    // MARK: - Notifications

    private func notifyPlaybackStateChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            NotificationCenter.default.post(
                name: Constants.Notifications.playbackStateChanged,
                object: nil,
                userInfo: ["state": self._playbackState.rawValue]
            )
        }
    }

    private func notifyCurrentTrackChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Constants.Notifications.trackDidChange,
                object: nil
            )
        }
    }
}

// MARK: - Supporting Types

enum PlaybackState: String {
    case playing
    case paused
    case stopped

    var displayName: String {
        switch self {
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .stopped:
            return "Stopped"
        }
    }
}
