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
    private var _replayGainMode: ReplayGainMode = .off

    private let stateLock = NSLock()
    private let playerQueue = DispatchQueue(label: "com.orangemusicplayer.player", qos: .userInitiated)

    // Keep references to players being cleaned up to prevent premature deallocation
    private var playersBeingCleaned: [AudioPlayer] = []
    private let cleanupLock = NSLock()

    private var playbackTimer: Timer?
    private var crossfadeTimer: Timer?
    private var _isCrossfading: Bool = false
    private var isCrossfading: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _isCrossfading }
        set { stateLock.lock(); _isCrossfading = newValue; stateLock.unlock() }
    }

    private let trackDAO = TrackDAO()
    private let playHistoryDAO = PlayHistoryDAO()
    private var currentPlayHistoryId: Int64?
    private var previousTrackForScrobble: Track?

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
        stateLock.lock()
        let player = audioPlayer
        stateLock.unlock()
        guard let player = player, player.isPlaying else {
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

    var replayGainMode: ReplayGainMode {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _replayGainMode
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
                    #if DEBUG
                    print("Failed to resume playback: \(error)")
                    #endif
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
                if let index = QueueManager.shared.indexOfTrack(track) {
                    _ = QueueManager.shared.skipToTrack(at: index)
                }
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

            // Finalize stats for the current track
            self.finalizeCurrentPlay()

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

            // Apply volume to AudioPlayer (with ReplayGain)
            if let player = self.audioPlayer {
                let vol = self.effectiveVolume(for: self._currentTrack)
                do {
                    try player.setVolume(vol)
                } catch {
                    #if DEBUG
                    print("Failed to set volume: \(error)")
                    #endif
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

    private var seekingDisabledForCurrentTrack = false

    private func performSeekOnQueue(_ time: TimeInterval) {
        guard let player = audioPlayer else { return }
        guard !seekingDisabledForCurrentTrack else { return }

        let duration = self.duration
        let clampedTime = min(max(0.0, time), duration)

        // Seek using AudioPlayer
        let seekSucceeded = player.seek(time: clampedTime)

        if !seekSucceeded {
            seekingDisabledForCurrentTrack = true
            #if DEBUG
            print("Seek failed: seeking not supported for this format")
            #endif
            return
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

    func setReplayGainMode(_ mode: ReplayGainMode) {
        stateLock.lock()
        _replayGainMode = mode
        stateLock.unlock()

        UserDefaults.standard.set(mode.rawValue, forKey: Constants.UserDefaultsKeys.replayGainMode)

        // Re-apply volume with new ReplayGain setting
        applyVolumeWithReplayGain()
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

    // MARK: - ReplayGain

    private func effectiveVolume(for track: Track?) -> Float {
        let baseVolume = _volume
        guard let track = track else { return baseVolume }

        let gainDB: Double?
        switch _replayGainMode {
        case .off:
            return baseVolume
        case .track:
            gainDB = track.replayGainTrackGain
        case .album:
            gainDB = track.replayGainAlbumGain ?? track.replayGainTrackGain
        }

        guard let gain = gainDB else { return baseVolume }

        // Convert dB gain to linear multiplier and apply to volume
        let multiplier = Float(pow(10.0, gain / 20.0))
        return min(max(0.0, baseVolume * multiplier), 1.0)
    }

    private func applyVolumeWithReplayGain() {
        playerQueue.async { [weak self] in
            guard let self = self, let player = self.audioPlayer else { return }
            let vol = self.effectiveVolume(for: self._currentTrack)
            do {
                try player.setVolume(vol)
            } catch {
                #if DEBUG
                print("Failed to apply ReplayGain volume: \(error)")
                #endif
            }
        }
    }

    /// Strip CUE virtual path suffix (e.g., "file.flac#track01" → "file.flac")
    /// Match sample rate synchronously using CoreAudio directly (no @MainActor needed)
    private static func matchSampleRateSync(trackSampleRate: Int?) {
        guard UserDefaults.standard.bool(forKey: "sampleRateSwitchingEnabled"),
              let trackRate = trackSampleRate, trackRate > 0,
              let device = AudioOutputManager.fetchCurrentDevice() else { return }

        let targetRate = Double(trackRate)
        let currentRate = AudioOutputManager.getDeviceSampleRate(device.id)

        guard abs(currentRate - targetRate) > 1.0 else { return }

        let supportedRates = AudioOutputManager.getSupportedSampleRates(device.id)
        guard supportedRates.contains(where: { $0.mMinimum <= targetRate && targetRate <= $0.mMaximum }) else { return }

        if AudioOutputManager.setDeviceSampleRate(device.id, sampleRate: targetRate) {
            DispatchQueue.main.async {
                AudioOutputManager.shared.currentSampleRate = targetRate
            }
        }
    }

    static func actualFilePath(for track: Track) -> String {
        let path = track.filePath
        if let hashIndex = path.lastIndex(of: "#"),
           path[hashIndex...].hasPrefix("#track") {
            return String(path[..<hashIndex])
        }
        return path
    }

    // MARK: - Private Methods - Player Cleanup

    /// Safely cleanup an AudioPlayer by stopping it and delaying deallocation
    /// This prevents crashes from internal AudioPlayerNode threads accessing freed memory
    private func safeCleanupPlayer(_ player: AudioPlayer?) {
        guard let player = player else { return }

        // Remove effect node tracking for this player's engine
        EQManager.shared.removeEQNode(for: player.audioEngine)
        ReverbManager.shared.removeNode(for: player.audioEngine)
        DelayManager.shared.removeNode(for: player.audioEngine)
        PitchSpeedManager.shared.removeNode(for: player.audioEngine)

        // Stop the player first
        player.stop()

        // Keep a strong reference to prevent immediate deallocation
        cleanupLock.lock()
        playersBeingCleaned.append(player)
        cleanupLock.unlock()

        // Delay cleanup to allow internal threads to finish
        // Hi-res decoders may need more time to wind down
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }

            self.cleanupLock.lock()
            self.playersBeingCleaned.removeAll { $0 === player }
            self.cleanupLock.unlock()

            // Player will be deallocated here after the delay
        }
    }

    // MARK: - Private Methods - Playback

    /// Finalize current play history entry before transitioning to another track
    private func finalizeCurrentPlay() {
        guard let playId = currentPlayHistoryId, let track = _currentTrack else { return }
        let currentTime = self.currentTime
        let duration = track.duration
        if duration > 0 && currentTime / duration > 0.8 {
            playHistoryDAO.markCompleted(playId: playId)
        }
        currentPlayHistoryId = nil
    }

    private func playTrack(_ track: Track) {
        // Must be called from playerQueue

        seekingDisabledForCurrentTrack = false

        // Finalize stats for the track we're leaving
        finalizeCurrentPlay()

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

        // Match output sample rate to track before playback
        Self.matchSampleRateSync(trackSampleRate: track.sampleRate)

        // Create URL for the track (strip CUE virtual path suffix)
        let url = URL(fileURLWithPath: Self.actualFilePath(for: track))

        // Create new AudioPlayer
        let player = AudioPlayer()

        do {
            player.delegate = self
            try player.play(url)

            // Insert effect chain into the audio graph after playback starts
            insertEffectNodes(into: player)

            // Set volume after starting playback (with ReplayGain)
            try player.setVolume(effectiveVolume(for: track))

            // Seek to start time for CUE tracks
            if let startTime = track.startTime, startTime > 0 {
                _ = player.seek(time: startTime)
            }

            audioPlayer = player
        } catch {
            #if DEBUG
            print("Failed to start playback: \(error)")
            #endif
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

        // Last.fm: update now playing + scrobble previous track
        if let prevTrack = previousTrackForScrobble {
            LastFMManager.shared.scrobbleIfEligible(track: prevTrack)
        }
        previousTrackForScrobble = track
        LastFMManager.shared.updateNowPlaying(track: track)

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

        // Match output sample rate to track before playback
        Self.matchSampleRateSync(trackSampleRate: track.sampleRate)

        // Create URL for the new track (strip CUE virtual path suffix)
        let url = URL(fileURLWithPath: Self.actualFilePath(for: track))

        // Create a new AudioPlayer for the incoming track
        let newPlayer = AudioPlayer()

        do {
            newPlayer.delegate = self
            try newPlayer.play(url)

            // Insert effect chain into the audio graph after playback starts
            insertEffectNodes(into: newPlayer)

            // Set volume to 0 after starting playback
            try newPlayer.setVolume(0.0)


            // Move current player to fading out
            fadingOutPlayer = currentPlayer
            audioPlayer = newPlayer


            // Perform volume ramping using a timer for smooth crossfade
            let steps = 50 // Number of volume adjustments
            let stepDuration = duration / Double(steps)

            // Capture volume under lock to avoid data race
            self.stateLock.lock()
            let targetVolume = self._volume
            self.stateLock.unlock()

            class CrossfadeState {
                var currentStep = 0
                var cancelled = false
            }
            let state = CrossfadeState()

            crossfadeTimer?.invalidate()

            // Schedule timer on main thread to ensure it fires reliably
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.crossfadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
                    guard let self = self, !state.cancelled else {
                        timer.invalidate()
                        return
                    }

                    // Capture current state under lock
                    self.stateLock.lock()
                    let capturedFadingOut = self.fadingOutPlayer
                    let capturedAudioPlayer = self.audioPlayer
                    self.stateLock.unlock()

                    state.currentStep += 1
                    let progress = Double(state.currentStep) / Double(steps)

                    // Crossfade volumes: old fades out, new fades in
                    let oldVolume = Float((1.0 - progress)) * targetVolume
                    let newVolume = Float(progress) * targetVolume

                    // Apply volumes to the captured player references
                    do {
                        if capturedFadingOut != nil {
                            try currentPlayer.setVolume(oldVolume)
                        }
                        if capturedAudioPlayer === newPlayer {
                            try newPlayer.setVolume(newVolume)
                        }
                    } catch {
                        #if DEBUG
                        print("Failed to set crossfade volume: \(error)")
                        #endif
                    }

                    if state.currentStep >= steps {
                        // Crossfade complete
                        timer.invalidate()
                        self.crossfadeTimer = nil

                        // Ensure final volume on new player
                        do {
                            if capturedAudioPlayer === newPlayer {
                                try newPlayer.setVolume(targetVolume)
                            }
                        } catch {
                            #if DEBUG
                            print("Failed to set final crossfade volume: \(error)")
                            #endif
                        }

                        // Cleanup old player safely
                        self.playerQueue.async { [weak self] in
                            guard let self = self else { return }

                            self.stateLock.lock()
                            let playerToClean = self.fadingOutPlayer
                            self.fadingOutPlayer = nil
                            self.stateLock.unlock()

                            self.safeCleanupPlayer(playerToClean)
                            self.isCrossfading = false
                        }
                    }
                }

                // Run the timer on the main run loop with common mode
                if let timer = self.crossfadeTimer {
                    RunLoop.main.add(timer, forMode: .common)
                }
            }

        } catch {
            #if DEBUG
            print("ERROR - Failed to start crossfade: \(error)")
            #endif
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

        let url = URL(fileURLWithPath: Self.actualFilePath(for: nextTrack))

        // Clean up previous next player safely
        safeCleanupPlayer(nextAudioPlayer)
        nextAudioPlayer = nil

        // Try to create and prepare next audio player
        let nextPlayer = AudioPlayer()

        do {
            nextPlayer.delegate = self
            try nextPlayer.play(url)
            insertEffectNodes(into: nextPlayer)
            nextPlayer.pause() // Pause immediately after loading

            // Set volume to 0
            try nextPlayer.setVolume(0.0)

            nextAudioPlayer = nextPlayer
        } catch {
            #if DEBUG
            print("Failed to prepare next track: \(error)")
            #endif
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
            #if DEBUG
            print("Failed to resume prepared player: \(error)")
            #endif
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

                // Check CUE end time
                if let endTime = self.currentTrack?.endTime, self.currentTime >= endTime {
                    self.playerQueue.async {
                        self.handleTrackNearingCompletion()
                    }
                    return
                }

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

        if let modeRaw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.replayGainMode),
           let mode = ReplayGainMode(rawValue: modeRaw) {
            _replayGainMode = mode
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
        // Copy current track under lock, then release before calling QueueManager
        // to avoid lock-ordering inversion (stateLock -> queueLock vs queueLock -> stateLock)
        stateLock.lock()
        let current = _currentTrack
        stateLock.unlock()

        guard let current = current else { return }

        if QueueManager.shared.indexOfTrack(current) == nil {
            let newTrack = QueueManager.shared.currentTrack

            stateLock.lock()
            _currentTrack = newTrack
            stateLock.unlock()

            notifyCurrentTrackChanged()
        }
    }

    // MARK: - Notifications

    private func notifyPlaybackStateChanged() {
        stateLock.lock()
        let stateRaw = _playbackState.rawValue
        stateLock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Constants.Notifications.playbackStateChanged,
                object: nil,
                userInfo: ["state": stateRaw]
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

        // Mark play as completed — track finished naturally so it's 100%
        if let playId = currentPlayHistoryId {
            playHistoryDAO.markCompleted(playId: playId)
            currentPlayHistoryId = nil
        }

        // Dispatch to playerQueue for thread-safe state management
        playerQueue.async { [weak self] in
            self?.handleTrackNearingCompletion()
        }
    }

    private func insertEffectNodes(into player: AudioPlayer) {
        let engine = player.audioEngine
        let mixer = engine.mainMixerNode

        // Find the actual source node connected to mainMixerNode input bus 0
        guard let connectionPoint = engine.inputConnectionPoint(for: mixer, inputBus: 0),
              let sourceNode = connectionPoint.node else { return }
        let format = mixer.inputFormat(forBus: 0)

        let eqNode = EQManager.shared.createEQNode(for: engine)
        let reverbNode = ReverbManager.shared.createNode(for: engine)
        let delayNode = DelayManager.shared.createNode(for: engine)
        let timePitchNode = PitchSpeedManager.shared.createNode(for: engine)

        engine.attach(eqNode)
        engine.attach(reverbNode)
        engine.attach(delayNode)
        engine.attach(timePitchNode)

        // Rewire: sourceNode → EQ → Reverb → Delay → TimePitch → mainMixerNode
        engine.disconnectNodeInput(mixer)
        engine.connect(sourceNode, to: eqNode, format: format)
        engine.connect(eqNode, to: reverbNode, format: format)
        engine.connect(reverbNode, to: delayNode, format: format)
        engine.connect(delayNode, to: timePitchNode, format: format)
        engine.connect(timePitchNode, to: mixer, format: format)

        #if DEBUG
        print("[AudioEffects] Inserted effect chain: source → EQ → Reverb → Delay → TimePitch → Mixer (format: \(format))")
        #endif
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, reconfigureProcessingGraph engine: AVAudioEngine, with format: AVAudioFormat) -> AVAudioNode {
        // Build chain: playerNode → EQ → Reverb → Delay → TimePitch → mainMixer
        let eqNode = EQManager.shared.createEQNode(for: engine)
        let reverbNode = ReverbManager.shared.createNode(for: engine)
        let delayNode = DelayManager.shared.createNode(for: engine)
        let timePitchNode = PitchSpeedManager.shared.createNode(for: engine)

        engine.attach(eqNode)
        engine.attach(reverbNode)
        engine.attach(delayNode)
        engine.attach(timePitchNode)

        engine.connect(eqNode, to: reverbNode, format: format)
        engine.connect(reverbNode, to: delayNode, format: format)
        engine.connect(delayNode, to: timePitchNode, format: format)
        engine.connect(timePitchNode, to: engine.mainMixerNode, format: format)

        // SFBAudioEngine connects playerNode → returned node
        #if DEBUG
        print("[AudioEffects] Chain built: EQ → Reverb → Delay → TimePitch → Mixer (format: \(format))")
        #endif
        return eqNode
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        #if DEBUG
        print("Asynchronous playback error: \(error)")
        #endif

        playerQueue.async { [weak self] in
            guard let self = self else { return }

            // On error, try to skip to next track
            self.next()
        }
    }
}

// MARK: - Supporting Types

enum ReplayGainMode: String, CaseIterable {
    case off = "off"
    case track = "track"
    case album = "album"

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .track: return "Track"
        case .album: return "Album"
        }
    }
}

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
