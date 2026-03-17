import Foundation
import AppKit
import SwiftUI
import Combine

@MainActor
class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    // MARK: - Published Properties

    @Published var currentTrack: Track?
    @Published var artwork: NSImage? {
        didSet {
            if let image = artwork {
                dominantColor = ColorExtractor.extractDominantColor(from: image)
            } else {
                dominantColor = nil
            }
        }
    }
    @Published var dominantColor: Color?
    @Published var artworkState: LoadingState = .idle
    @Published var lyrics: String?
    @Published var lyricsState: LoadingState = .idle
    @Published var playbackState: PlaybackState = .stopped
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

    private let nowPlayingQueue = DispatchQueue(label: "com.orangemusicplayer.nowplaying", qos: .userInitiated)

    // MARK: - Initialization

    private init() {
        setupNotificationObservers()
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

        // Shuffle mode changed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShuffleModeChanged(_:)),
            name: Constants.Notifications.shuffleModeChanged,
            object: nil
        )

        // Artwork did load (if artwork was loaded externally)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleArtworkDidLoad(_:)),
            name: Constants.Notifications.artworkDidLoad,
            object: nil
        )

        // Artwork changed (e.g. user picked new artwork via picker)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleArtworkDidChange(_:)),
            name: Constants.Notifications.artworkDidChange,
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

    private func loadInitialState() {
        currentTrack = queueManager.currentTrack
        playbackState = playerManager.playbackState
        volume = playerManager.volume
        isShuffleEnabled = queueManager.isShuffleEnabled
        repeatMode = queueManager.repeatMode
        queue = queueManager.currentQueue
        currentTrackIndex = queueManager.currentTrackIndex

        // Load artwork and lyrics for current track
        if currentTrack != nil {
            loadArtwork()
            loadLyrics()
        }
    }

    // MARK: - Notification Handlers

    @objc private func handleTrackDidChange(_ notification: Notification) {
        let previousTrack = currentTrack
        currentTrack = queueManager.currentTrack
        currentTrackIndex = queueManager.currentTrackIndex

        // Only reload if track actually changed
        if previousTrack?.id != currentTrack?.id {
            clearCache()

            if currentTrack != nil {
                loadArtwork()
                loadLyrics()
            }

            preloadNextTrack()
        }
    }

    @objc private func handlePlaybackStateChanged(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let stateRawValue = userInfo["state"] as? String,
           let state = PlaybackState(rawValue: stateRawValue) {
            playbackState = state
        }
    }

    @objc private func handleVolumeChanged(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let vol = userInfo["volume"] as? Float {
            volume = vol
        }
    }

    @objc private func handleQueueDidChange(_ notification: Notification) {
        queue = queueManager.currentQueue
        currentTrackIndex = queueManager.currentTrackIndex
        isShuffleEnabled = queueManager.isShuffleEnabled
    }

    @objc private func handleRepeatModeChanged(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let modeRawValue = userInfo["repeatMode"] as? String,
           let mode = RepeatMode(rawValue: modeRawValue) {
            repeatMode = mode
        }
    }

    @objc private func handleShuffleModeChanged(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let shuffleEnabled = userInfo["shuffleEnabled"] as? Bool {
            isShuffleEnabled = shuffleEnabled
        }
    }

    @objc private func handleArtworkDidChange(_ notification: Notification) {
        if let albumId = notification.userInfo?["albumId"] as? Int64,
           currentTrack?.albumId == albumId {
            artworkManager.clearAlbumCache(
                albumTitle: currentTrack?.albumTitle ?? "",
                artistName: currentTrack?.albumArtistName ?? currentTrack?.artistName
            )
            loadArtwork(force: true)
        }
    }

    @objc private func handleArtworkDidLoad(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let trackId = userInfo["trackId"] as? Int64,
           let image = userInfo["artwork"] as? NSImage,
           trackId == currentTrack?.id {
            artwork = image
            artworkState = .loaded
        }
    }

    @objc private func handleLyricsDidLoad(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let trackId = userInfo["trackId"] as? Int64,
           let lyricsText = userInfo["lyrics"] as? String,
           trackId == currentTrack?.id {
            lyrics = lyricsText
            lyricsState = .loaded
        }
    }

    @objc private func handleTrackFavoriteChanged(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let trackId = userInfo["trackId"] as? Int64,
           trackId == currentTrack?.id {
            let dao = TrackDAO()
            nowPlayingQueue.async { [weak self] in
                if let updatedTrack = dao.getById(id: trackId) {
                    DispatchQueue.main.async {
                        self?.currentTrack = updatedTrack
                    }
                }
            }
        }
    }

    // MARK: - Cleanup

    deinit {
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
