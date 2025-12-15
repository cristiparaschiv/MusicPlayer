import Foundation
import SFBAudioEngine
import AVFoundation
import CoreAudio

class PlayerManager: NSObject {
    static let shared = PlayerManager()

    // MARK: - Audio Player

    private var audioPlayer: AudioPlayer?
    private var nextAudioPlayer: AudioPlayer? // For gapless playback
    private var fadingOutPlayer: AudioPlayer? // For crossfade

    // MARK: - State

    private var _playbackState: PlaybackState = .stopped
    private var _currentTrack: Track?
    private var _volume: Float = Constants.defaultVolume
    private var _isCrossfadeEnabled: Bool = false
    private var _crossfadeDuration: TimeInterval = Constants.defaultCrossfadeDuration
    private var _isGaplessEnabled: Bool = true

    private let stateLock = NSLock()
    private let playerQueue = DispatchQueue(label: "com.orangemusicplayer.player", qos: .userInitiated)

    // Keep references to players being cleaned up to prevent premature deallocation
    private var playersBeingCleaned: [AudioPlayer] = []
    private let cleanupLock = NSLock()

    private var playbackTimer: Timer?
    private var crossfadeTimer: Timer?
    private var isCrossfading: Bool = false

    private let trackDAO = TrackDAO()
    private let playHistoryDAO = PlayHistoryDAO()
    private var currentPlayHistoryId: Int64?

    // MARK: - Initialization

    private override init() {
        super.init()
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

    var crossfadeDuration: TimeInterval {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _crossfadeDuration
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
                    try player.resume()
                    self._playbackState = .playing
                    self.stateLock.unlock()

                    self.notifyPlaybackStateChanged()
                    self.startPlaybackTimer()
                } catch {
                    print("Failed to resume playback: \(error)")
                    self.stateLock.unlock()
                }
                return
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

            // Cleanup current playback safely
            self.safeCleanupPlayer(self.audioPlayer)
            self.audioPlayer = nil

            self.safeCleanupPlayer(self.nextAudioPlayer)
            self.nextAudioPlayer = nil

            self.safeCleanupPlayer(self.fadingOutPlayer)
            self.fadingOutPlayer = nil

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

            // Invalidate timers first
            DispatchQueue.main.async {
                self.crossfadeTimer?.invalidate()
                self.crossfadeTimer = nil
            }

            self.stateLock.lock()

            // Stop all players safely
            self.safeCleanupPlayer(self.audioPlayer)
            self.audioPlayer = nil

            self.safeCleanupPlayer(self.nextAudioPlayer)
            self.nextAudioPlayer = nil

            self.safeCleanupPlayer(self.fadingOutPlayer)
            self.fadingOutPlayer = nil

            self.isCrossfading = false

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

            // Apply volume to AudioPlayer
            if let player = self.audioPlayer {
                do {
                    try player.setVolume(clampedVolume)
                } catch {
                    print("Failed to set volume: \(error)")
                }
            }

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
        guard let player = audioPlayer else { return }

        let duration = self.duration
        let clampedTime = min(max(0.0, time), duration)

        // Seek using AudioPlayer
        let seekSucceeded = player.seek(time: clampedTime)

        if !seekSucceeded {
            print("Seek failed: seeking not supported for this format")
        }

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

    // MARK: - Private Methods - Player Cleanup

    /// Safely cleanup an AudioPlayer by stopping it and delaying deallocation
    /// This prevents crashes from internal AudioPlayerNode threads accessing freed memory
    private func safeCleanupPlayer(_ player: AudioPlayer?) {
        guard let player = player else { return }

        // Stop the player first
        player.stop()

        // Keep a strong reference to prevent immediate deallocation
        cleanupLock.lock()
        playersBeingCleaned.append(player)
        cleanupLock.unlock()

        // Delay cleanup to allow internal threads to finish
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            self.cleanupLock.lock()
            self.playersBeingCleaned.removeAll { $0 === player }
            self.cleanupLock.unlock()

            // Player will be deallocated here after the delay
        }
    }

    // MARK: - Private Methods - Playback

    private func playTrack(_ track: Track) {
        // Must be called from playerQueue

        let shouldCrossfade = _isCrossfadeEnabled && audioPlayer != nil && audioPlayer!.isPlaying

        if shouldCrossfade {
            performCrossfadeToTrack(track)
        } else {
            performNormalTransitionToTrack(track)
        }
    }

    private func performNormalTransitionToTrack(_ track: Track) {
        // Cleanup any existing playback safely
        safeCleanupPlayer(audioPlayer)
        audioPlayer = nil

        safeCleanupPlayer(fadingOutPlayer)
        fadingOutPlayer = nil

        safeCleanupPlayer(nextAudioPlayer)
        nextAudioPlayer = nil

        DispatchQueue.main.async { [weak self] in
            self?.crossfadeTimer?.invalidate()
            self?.crossfadeTimer = nil
        }
        isCrossfading = false

        // Create URL for the track
        let url = URL(fileURLWithPath: track.filePath)

        // Create new AudioPlayer
        let player = AudioPlayer()

        do {
            // Setup completion callback BEFORE playing
            player.delegate = self

            // Play the track
            try player.play(url)

            // Set volume after starting playback
            try player.setVolume(_volume)

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

        // Record play history immediately
        currentPlayHistoryId = playHistoryDAO.recordPlay(trackId: track.id)

        // Update play count after a few seconds (to avoid counting skips)
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self,
                  self._currentTrack?.id == track.id,
                  self.isPlaying else { return }

            self.trackDAO.updatePlayCount(trackId: track.id)
        }

        // Prepare next track for gapless playback
        if _isGaplessEnabled || _isCrossfadeEnabled {
            prepareNextTrack()
        }

        notifyPlaybackStateChanged()
        notifyCurrentTrackChanged()
        startPlaybackTimer()
    }

    private func performCrossfadeToTrack(_ track: Track) {
        // Must be called from playerQueue
        guard let currentPlayer = audioPlayer else {
            performNormalTransitionToTrack(track)
            return
        }


        // Get the crossfade duration
        let duration = _crossfadeDuration

        // Create URL for the new track
        let url = URL(fileURLWithPath: track.filePath)

        // Create a new AudioPlayer for the incoming track
        let newPlayer = AudioPlayer()

        do {
            // Setup completion callbacks for the new player
            newPlayer.delegate = self

            // Start playback on the new player at zero volume
            try newPlayer.play(url)

            // Set volume to 0 after starting playback
            try newPlayer.setVolume(0.0)


            // Move current player to fading out
            fadingOutPlayer = currentPlayer
            audioPlayer = newPlayer


            // Perform volume ramping using a timer for smooth crossfade
            let steps = 50 // Number of volume adjustments
            let stepDuration = duration / Double(steps)

            class CrossfadeState {
                var currentStep = 0
            }
            let state = CrossfadeState()

            crossfadeTimer?.invalidate()

            // Schedule timer on main thread to ensure it fires reliably
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.crossfadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
                    guard let self = self else {
                        timer.invalidate()
                        return
                    }

                    state.currentStep += 1
                    let progress = Double(state.currentStep) / Double(steps)

                    // Crossfade volumes: old fades out, new fades in
                    let oldVolume = Float((1.0 - progress)) * self._volume
                    let newVolume = Float(progress) * self._volume

                    // Apply volumes to the players
                    do {
                        try currentPlayer.setVolume(oldVolume)
                        try newPlayer.setVolume(newVolume)
                    } catch {
                        print("Failed to set crossfade volume: \(error)")
                    }

                    if state.currentStep >= steps {
                        // Crossfade complete
                        timer.invalidate()
                        self.crossfadeTimer = nil

                        // Ensure final volumes are set
                        do {
                            try currentPlayer.setVolume(0.0)
                            try newPlayer.setVolume(self._volume)
                        } catch {
                            print("Failed to set final crossfade volume: \(error)")
                        }

                        // Cleanup old player safely
                        self.playerQueue.async { [weak self] in
                            guard let self = self else { return }

                            self.safeCleanupPlayer(self.fadingOutPlayer)
                            self.fadingOutPlayer = nil
                            self.isCrossfading = false
                        }
                    }
                }

                // Run the timer on the main run loop with common mode
                RunLoop.main.add(self.crossfadeTimer!, forMode: .common)
            }

        } catch {
            print("ERROR - Failed to start crossfade: \(error)")
            // Clean up the failed new player if it exists
            safeCleanupPlayer(newPlayer)
            // Fall back to normal transition
            performNormalTransitionToTrack(track)
            return
        }

        stateLock.lock()
        _playbackState = .playing
        stateLock.unlock()

        // Record play history immediately
        currentPlayHistoryId = playHistoryDAO.recordPlay(trackId: track.id)

        // Update play count after a few seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self,
                  self._currentTrack?.id == track.id,
                  self.isPlaying else { return }

            self.trackDAO.updatePlayCount(trackId: track.id)
        }

        // Prepare next track
        if _isGaplessEnabled || _isCrossfadeEnabled {
            prepareNextTrack()
        }

        notifyCurrentTrackChanged()
    }

    private func prepareNextTrack() {
        // Must be called from playerQueue
        guard _isGaplessEnabled || _isCrossfadeEnabled else { return }
        guard let nextTrack = QueueManager.shared.peekNext() else {
            safeCleanupPlayer(nextAudioPlayer)
            nextAudioPlayer = nil
            return
        }

        // Don't prepare if we're in repeat one mode (same track)
        if QueueManager.shared.repeatMode == .one {
            safeCleanupPlayer(nextAudioPlayer)
            nextAudioPlayer = nil
            return
        }

        let url = URL(fileURLWithPath: nextTrack.filePath)

        // Clean up previous next player safely
        safeCleanupPlayer(nextAudioPlayer)
        nextAudioPlayer = nil

        // Try to create and prepare next audio player
        let nextPlayer = AudioPlayer()

        do {
            // For gapless playback, we pre-load the next track
            try nextPlayer.play(url)
            nextPlayer.pause() // Pause immediately after loading

            // Set volume to 0
            try nextPlayer.setVolume(0.0)

            nextAudioPlayer = nextPlayer
        } catch {
            print("Failed to prepare next track: \(error)")
            nextAudioPlayer = nil
        }
    }


    private func handleTrackNearingCompletion() {
        // Must be called from playerQueue

        // Check if crossfade is enabled and should start early
        if _isCrossfadeEnabled && !isCrossfading && QueueManager.shared.hasNext {
            isCrossfading = true
            // Use peekNext() to see what's coming WITHOUT advancing the queue
            // Then call next() to advance the queue and get the actual track to play
            if let nextTrack = QueueManager.shared.peekNext() {
                // Now advance the queue to make this the current track
                _ = QueueManager.shared.next()
                stateLock.lock()
                _currentTrack = nextTrack
                stateLock.unlock()
                performCrossfadeToTrack(nextTrack)
                return
            }
        }

        // For gapless playback, transition to next track
        if _isGaplessEnabled && QueueManager.shared.hasNext {
            handleTrackCompletion()
        } else if QueueManager.shared.hasNext {
            // Normal transition
            handleTrackCompletion()
        } else {
            // No more tracks, stop playback
            stop()
        }
    }

    private func handleTrackCompletion() {
        // Track finished playing, move to next
        // Must be called from playerQueue

        if QueueManager.shared.hasNext {
            if _isGaplessEnabled && nextAudioPlayer != nil {
                // Use pre-buffered next track for gapless transition
                performGaplessTransition()
            } else {
                // Normal transition to next track
                next()
            }
        } else {
            // No more tracks, stop playback
            stop()
        }
    }

    private func performGaplessTransition() {
        // Must be called from playerQueue
        guard let preparedNextPlayer = nextAudioPlayer,
              let nextTrack = QueueManager.shared.next() else {
            next()
            return
        }

        // Stop current player safely
        safeCleanupPlayer(audioPlayer)

        // Switch to prepared next player
        do {
            try preparedNextPlayer.setVolume(_volume)
            try preparedNextPlayer.resume()
        } catch {
            print("Failed to resume prepared player: \(error)")
            next()
            return
        }

        audioPlayer = preparedNextPlayer
        nextAudioPlayer = nil

        stateLock.lock()
        _currentTrack = nextTrack
        _playbackState = .playing
        stateLock.unlock()

        // Record play history immediately
        currentPlayHistoryId = playHistoryDAO.recordPlay(trackId: nextTrack.id)

        // Update play count after a few seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self,
                  self._currentTrack?.id == nextTrack.id,
                  self.isPlaying else { return }

            self.trackDAO.updatePlayCount(trackId: nextTrack.id)
        }

        // Prepare the next track in the queue
        if _isGaplessEnabled || _isCrossfadeEnabled {
            prepareNextTrack()
        }

        notifyCurrentTrackChanged()
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

    private func loadPersistedSettings() {
        _volume = UserDefaults.standard.float(forKey: Constants.UserDefaultsKeys.volume)
        if _volume == 0 {
            _volume = Constants.defaultVolume
        }

        // Crossfade should default to enabled
        if UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.crossfadeEnabled) != nil {
            _isCrossfadeEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.crossfadeEnabled)
        } else {
            _isCrossfadeEnabled = true
            UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.crossfadeEnabled)
        }

        // Gapless playback should default to enabled
        if UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.gaplessPlaybackEnabled) != nil {
            _isGaplessEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.gaplessPlaybackEnabled)
        } else {
            _isGaplessEnabled = true
            UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.gaplessPlaybackEnabled)
        }

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

// MARK: - AudioPlayerDelegate

extension PlayerManager: AudioPlayer.Delegate {
    func audioPlayer(_ audioPlayer: AudioPlayer, renderingComplete decoder: any PCMDecoding) {

        // Mark play as completed if >80% of track was played
        if let playId = currentPlayHistoryId, let track = currentTrack {
            let currentTime = self.currentTime
            let duration = track.duration
            if duration > 0 && currentTime / duration > 0.8 {
                playHistoryDAO.markCompleted(playId: playId)
            }
        }

        // Dispatch to playerQueue for thread-safe state management
        playerQueue.async { [weak self] in
            self?.handleTrackNearingCompletion()
        }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        print("Asynchronous playback error: \(error)")

        playerQueue.async { [weak self] in
            guard let self = self else { return }

            // On error, try to skip to next track
            self.next()
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
