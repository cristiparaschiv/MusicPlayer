import Foundation
import MediaPlayer
import AppKit

/// Integrates with macOS system media controls:
/// - Media keys (F7/F8/F9 play/pause/next/previous)
/// - Now Playing info in Control Center / menu bar widget
/// - MPRemoteCommandCenter for external control (headphones, Touch Bar, etc.)
nonisolated(unsafe) class SystemMediaIntegrationManager: @unchecked Sendable {
    static let shared = SystemMediaIntegrationManager()

    private let commandCenter = MPRemoteCommandCenter.shared()
    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let playerManager = PlayerManager.shared
    private let queueManager = QueueManager.shared

    private init() {
        setupRemoteCommands()
        setupNotificationObservers()
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommands() {
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.playerManager.play()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.playerManager.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.playerManager.togglePlayPause()
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.playerManager.next()
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.playerManager.previous()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.playerManager.seek(to: positionEvent.positionTime)
            return .success
        }
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTrackDidChange),
            name: Constants.Notifications.trackDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackStateChanged),
            name: Constants.Notifications.playbackStateChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackTimeChanged),
            name: Constants.Notifications.playbackTimeChanged,
            object: nil
        )
    }

    // MARK: - Now Playing Info Updates

    @objc private func handleTrackDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateNowPlayingInfo()
        }
    }

    @objc private func handlePlaybackStateChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let userInfo = notification.userInfo,
               let stateRaw = userInfo["state"] as? String,
               let state = PlaybackState(rawValue: stateRaw) {
                switch state {
                case .playing:
                    self.infoCenter.playbackState = .playing
                case .paused:
                    self.infoCenter.playbackState = .paused
                case .stopped:
                    self.infoCenter.playbackState = .stopped
                    self.infoCenter.nowPlayingInfo = nil
                    return
                }
            }
            self.updateElapsedTime()
        }
    }

    @objc private func handlePlaybackTimeChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateElapsedTime()
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = playerManager.currentTrack else {
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .stopped
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: playerManager.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: playerManager.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if let artist = track.artistName {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = track.albumTitle {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let trackNumber = track.trackNumber, trackNumber > 0 {
            info[MPMediaItemPropertyAlbumTrackNumber] = trackNumber
        }

        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = playerManager.isPlaying ? .playing : .paused

        // Load artwork asynchronously
        let trackId = track.id
        ArtworkManager.shared.fetchArtworkFromTrack(track) { [weak self] result in
            switch result {
            case .success(let image):
                self?.applyArtwork(image, forTrackId: trackId)
            case .failure:
                if let album = track.albumTitle,
                   let artist = track.albumArtistName ?? track.artistName {
                    ArtworkManager.shared.fetchAlbumArtwork(albumTitle: album, artistName: artist) { [weak self] result in
                        if case .success(let image) = result {
                            self?.applyArtwork(image, forTrackId: trackId)
                        }
                    }
                }
            }
        }
    }

    private func updateElapsedTime() {
        guard var info = infoCenter.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playerManager.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = playerManager.isPlaying ? 1.0 : 0.0
        infoCenter.nowPlayingInfo = info
    }

    private func applyArtwork(_ nsImage: NSImage, forTrackId trackId: Int64) {
        // Capture the image data on the current thread to avoid passing NSImage across threads unsafely
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        let size = nsImage.size

        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  self.playerManager.currentTrack?.id == trackId,
                  var info = self.infoCenter.nowPlayingInfo else { return }

            let artwork = MPMediaItemArtwork(boundsSize: size) { _ in
                // Reconstruct NSImage from data — safe to call from any thread
                return NSImage(data: pngData) ?? NSImage()
            }
            info[MPMediaItemPropertyArtwork] = artwork
            self.infoCenter.nowPlayingInfo = info
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
    }
}
