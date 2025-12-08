import Foundation
import AppKit
import Combine

class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    // MARK: - Published Properties

    @Published var currentTrack: Track?
    @Published var artwork: NSImage?
    @Published var artworkState: LoadingState = .idle
    @Published var lyrics: String?
    @Published var lyricsState: LoadingState = .idle
    @Published var playbackState: PlaybackState = .stopped
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 0.8
    @Published var isShuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var queue: [Track] = []
    @Published var currentTrackIndex: Int = -1

    // MARK: - Private Properties

    private let playerManager = PlayerManager.shared
    private let queueManager = QueueManager.shared
    private let artworkManager = ArtworkManager.shared
    private let lyricsManager = LyricsManager.shared

    private var cancellables = Set<AnyCancellable>()
    private var playbackTimeTimer: Timer?

    private let nowPlayingQueue = DispatchQueue(label: "com.orangemusicplayer.nowplaying", qos: .userInitiated)

    // MARK: - Initialization

    private init() {
        setupNotificationObservers()
        setupPlaybackTimeTimer()
        loadInitialState()
    }

    // MARK: - Public Methods - Data Loading

    /// Load artwork for current track
    func loadArtwork(force: Bool = false) {
        guard let track = currentTrack else {
            artworkState = .idle
            artwork = nil
            return
        }

        if !force && artwork != nil {
            return
        }

        artworkState = .loading

        // Try to extract from track file first
        artworkManager.fetchArtworkFromTrack(track) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let image):
                DispatchQueue.main.async {
                    self.artwork = image
                    self.artworkState = .loaded
                }

            case .failure:
                // Fallback to MusicBrainz if metadata extraction fails
                if let albumTitle = track.albumTitle, let artistName = track.albumArtistName ?? track.artistName {
                    self.artworkManager.fetchAlbumArtwork(albumTitle: albumTitle, artistName: artistName) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let image):
                                self.artwork = image
                                self.artworkState = .loaded

                            case .failure(let error):
                                self.artwork = nil
                                self.artworkState = .failed(error.localizedDescription)
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.artwork = nil
                        self.artworkState = .failed("No album information")
                    }
                }
            }
        }
    }

    /// Load lyrics for current track
    func loadLyrics(force: Bool = false) {
        guard let track = currentTrack else {
            lyricsState = .idle
            lyrics = nil
            return
        }

        if !force && lyrics != nil {
            return
        }

        lyricsState = .loading

        lyricsManager.fetchLyrics(for: track) { [weak self] result in
            guard let self = self else { return }

            DispatchQueue.main.async {
                switch result {
                case .success(let lyricsText):
                    self.lyrics = lyricsText
                    self.lyricsState = .loaded

                case .failure(let error):
                    self.lyrics = nil
                    self.lyricsState = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Preload data for the next track in queue
    func preloadNextTrack() {
        guard let nextTrack = queueManager.peekNext() else { return }

        nowPlayingQueue.async { [weak self] in
            guard let self = self else { return }

            // Preload artwork
            self.artworkManager.fetchArtworkFromTrack(nextTrack) { _ in
                // Result is cached, no need to handle
            }

            // Don't preload lyrics as they might not be needed
        }
    }

    /// Reload all data for current track
    func reloadCurrentTrack() {
        loadArtwork(force: true)
        // Don't auto-load lyrics, only when explicitly requested
    }

    /// Clear all cached data
    func clearCache() {
        artwork = nil
        lyrics = nil
        artworkState = .idle
        lyricsState = .idle
    }

    // MARK: - Public Methods - Playback Control

    /// Play/pause toggle
    func togglePlayPause() {
        playerManager.togglePlayPause()
    }

    /// Play specific track
    func play(track: Track) {
        playerManager.play(track: track)
    }

    /// Next track
    func next() {
        playerManager.next()
    }

    /// Previous track
    func previous() {
        playerManager.previous()
    }

    /// Seek to time
    func seek(to time: TimeInterval) {
        playerManager.seek(to: time)
    }

    /// Set volume
    func setVolume(_ volume: Float) {
        playerManager.setVolume(volume)
    }

    /// Toggle shuffle
    func toggleShuffle() {
        queueManager.toggleShuffle()
    }

    /// Cycle repeat mode
    func cycleRepeatMode() {
        queueManager.cycleRepeatMode()
    }

    /// Toggle favorite
    func toggleFavorite() {
        guard let track = currentTrack else { return }
        playerManager.toggleFavorite(track: track)
    }

    // MARK: - Private Methods - Initialization

    private func setupNotificationObservers() {
        // Track did change
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTrackDidChange(_:)),
            name: Constants.Notifications.trackDidChange,
            object: nil
        )

        // Playback state changed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackStateChanged(_:)),
            name: Constants.Notifications.playbackStateChanged,
            object: nil
        )

        // Volume changed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVolumeChanged(_:)),
            name: Constants.Notifications.volumeChanged,
            object: nil
        )

        // Queue did change
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQueueDidChange(_:)),
            name: Constants.Notifications.queueDidChange,
            object: nil
        )

        // Repeat mode changed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRepeatModeChanged(_:)),
            name: Constants.Notifications.repeatModeChanged,
            object: nil
        )

        // Artwork did load (if artwork was loaded externally)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleArtworkDidLoad(_:)),
            name: Constants.Notifications.artworkDidLoad,
            object: nil
        )

        // Lyrics did load (if lyrics were loaded externally)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLyricsDidLoad(_:)),
            name: Constants.Notifications.lyricsDidLoad,
            object: nil
        )

        // Track favorite changed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTrackFavoriteChanged(_:)),
            name: Constants.Notifications.trackFavoriteChanged,
            object: nil
        )
    }

    private func setupPlaybackTimeTimer() {
        playbackTimeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.currentTime = self.playerManager.currentTime
                self.duration = self.playerManager.duration
            }
        }
    }

    private func loadInitialState() {
        DispatchQueue.main.async {
            self.currentTrack = self.queueManager.currentTrack
            self.playbackState = self.playerManager.playbackState
            self.currentTime = self.playerManager.currentTime
            self.duration = self.playerManager.duration
            self.volume = self.playerManager.volume
            self.isShuffleEnabled = self.queueManager.isShuffleEnabled
            self.repeatMode = self.queueManager.repeatMode
            self.queue = self.queueManager.currentQueue
            self.currentTrackIndex = self.queueManager.currentTrackIndex

            // Load artwork for current track
            if self.currentTrack != nil {
                self.loadArtwork()
            }
        }
    }

    // MARK: - Notification Handlers

    @objc private func handleTrackDidChange(_ notification: Notification) {
        DispatchQueue.main.async {
            let previousTrack = self.currentTrack
            self.currentTrack = self.queueManager.currentTrack
            self.currentTrackIndex = self.queueManager.currentTrackIndex

            // Only reload if track actually changed
            if previousTrack?.id != self.currentTrack?.id {
                // Clear previous data
                self.clearCache()

                // Load new data
                if self.currentTrack != nil {
                    self.loadArtwork()
                    // Don't auto-load lyrics, only when user opens lyrics view
                }

                // Preload next track
                self.preloadNextTrack()
            }
        }
    }

    @objc private func handlePlaybackStateChanged(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let stateRawValue = userInfo["state"] as? String,
           let state = PlaybackState(rawValue: stateRawValue) {
            DispatchQueue.main.async {
                self.playbackState = state
            }
        }
    }

    @objc private func handleVolumeChanged(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let volume = userInfo["volume"] as? Float {
            DispatchQueue.main.async {
                self.volume = volume
            }
        }
    }

    @objc private func handleQueueDidChange(_ notification: Notification) {
        DispatchQueue.main.async {
            self.queue = self.queueManager.currentQueue
            self.isShuffleEnabled = self.queueManager.isShuffleEnabled
        }
    }

    @objc private func handleRepeatModeChanged(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let modeRawValue = userInfo["repeatMode"] as? String,
           let mode = RepeatMode(rawValue: modeRawValue) {
            DispatchQueue.main.async {
                self.repeatMode = mode
            }
        }
    }

    @objc private func handleArtworkDidLoad(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let trackId = userInfo["trackId"] as? Int64,
           let image = userInfo["artwork"] as? NSImage,
           trackId == currentTrack?.id {
            DispatchQueue.main.async {
                self.artwork = image
                self.artworkState = .loaded
            }
        }
    }

    @objc private func handleLyricsDidLoad(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let trackId = userInfo["trackId"] as? Int64,
           let lyricsText = userInfo["lyrics"] as? String,
           trackId == currentTrack?.id {
            DispatchQueue.main.async {
                self.lyrics = lyricsText
                self.lyricsState = .loaded
            }
        }
    }

    @objc private func handleTrackFavoriteChanged(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let trackId = userInfo["trackId"] as? Int64,
           let isFavorite = userInfo["isFavorite"] as? Bool,
           trackId == currentTrack?.id {
            // Note: Track is a struct, so the favorite status will be reflected when track is reloaded
            print("Track \(trackId) favorite status changed to \(isFavorite)")
        }
    }

    // MARK: - Cleanup

    deinit {
        playbackTimeTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Supporting Types

enum LoadingState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var errorMessage: String? {
        if case .failed(let message) = self {
            return message
        }
        return nil
    }
}
