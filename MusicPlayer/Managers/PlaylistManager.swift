import Foundation

class PlaylistManager {
    static let shared = PlaylistManager()

    private let playlistDAO = PlaylistDAO()
    private let trackDAO = TrackDAO()
    private let playlistQueue = DispatchQueue(label: "com.orangemusicplayer.playlists", qos: .userInitiated)

    private init() {}

    // MARK: - Playlist CRUD Operations

    /// Create a new playlist
    func createPlaylist(name: String, isSmartPlaylist: Bool = false, smartCriteria: String? = nil, completion: ((Result<Playlist, PlaylistError>) -> Void)? = nil) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            // Validate name
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.callCompletion(completion, with: .failure(.invalidName))
                return
            }

            // Check for duplicate name
            let existingPlaylists = self.playlistDAO.getAll()
            if existingPlaylists.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                self.callCompletion(completion, with: .failure(.duplicateName))
                return
            }

            // Create playlist
            let now = Date()
            let tempPlaylist = Playlist(
                id: 0, // Will be replaced with actual ID
                name: name,
                dateCreated: now,
                dateModified: now,
                isSmartPlaylist: isSmartPlaylist,
                smartCriteria: smartCriteria,
                trackCount: 0
            )

            let playlistId = self.playlistDAO.insert(playlist: tempPlaylist)

            // Fetch the created playlist
            guard let newPlaylist = self.playlistDAO.getById(id: playlistId) else {
                self.callCompletion(completion, with: .failure(.creationFailed))
                return
            }

            // Post notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.playlistsChanged,
                    object: nil,
                    userInfo: ["action": "created", "playlistId": playlistId]
                )
            }

            self.callCompletion(completion, with: .success(newPlaylist))
        }
    }

    /// Get all playlists
    func getPlaylists(completion: @escaping (Result<[Playlist], PlaylistError>) -> Void) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            let playlists = self.playlistDAO.getAll()
            self.callCompletion(completion, with: .success(playlists))
        }
    }

    /// Get all playlists synchronously (for convenience)
    func getPlaylists() -> [Playlist] {
        return playlistDAO.getAll()
    }

    /// Get a specific playlist by ID
    func getPlaylist(id: Int64, completion: @escaping (Result<Playlist, PlaylistError>) -> Void) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            guard let playlist = self.playlistDAO.getById(id: id) else {
                self.callCompletion(completion, with: .failure(.notFound))
                return
            }

            self.callCompletion(completion, with: .success(playlist))
        }
    }

    /// Update playlist name or smart criteria
    func updatePlaylist(id: Int64, name: String? = nil, smartCriteria: String? = nil, completion: ((Result<Playlist, PlaylistError>) -> Void)? = nil) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            guard var playlist = self.playlistDAO.getById(id: id) else {
                self.callCompletion(completion, with: .failure(.notFound))
                return
            }

            // Update name if provided
            if let newName = name {
                guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.callCompletion(completion, with: .failure(.invalidName))
                    return
                }

                // Check for duplicate name (excluding current playlist)
                let existingPlaylists = self.playlistDAO.getAll()
                if existingPlaylists.contains(where: { $0.id != id && $0.name.lowercased() == newName.lowercased() }) {
                    self.callCompletion(completion, with: .failure(.duplicateName))
                    return
                }

                playlist = Playlist(
                    id: playlist.id,
                    name: newName,
                    dateCreated: playlist.dateCreated,
                    dateModified: Date(),
                    isSmartPlaylist: playlist.isSmartPlaylist,
                    smartCriteria: smartCriteria ?? playlist.smartCriteria,
                    trackCount: playlist.trackCount
                )
            } else if let newCriteria = smartCriteria {
                playlist = Playlist(
                    id: playlist.id,
                    name: playlist.name,
                    dateCreated: playlist.dateCreated,
                    dateModified: Date(),
                    isSmartPlaylist: playlist.isSmartPlaylist,
                    smartCriteria: newCriteria,
                    trackCount: playlist.trackCount
                )
            }

            self.playlistDAO.update(playlist: playlist)

            // Post notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.playlistsChanged,
                    object: nil,
                    userInfo: ["action": "updated", "playlistId": id]
                )
            }

            self.callCompletion(completion, with: .success(playlist))
        }
    }

    /// Delete a playlist
    func deletePlaylist(id: Int64, completion: ((Result<Void, PlaylistError>) -> Void)? = nil) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.playlistDAO.getById(id: id) != nil else {
                self.callCompletion(completion, with: .failure(.notFound))
                return
            }

            self.playlistDAO.delete(playlistId: id)

            // Post notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.playlistsChanged,
                    object: nil,
                    userInfo: ["action": "deleted", "playlistId": id]
                )
            }

            self.callCompletion(completion, with: .success(()))
        }
    }

    /// Delete multiple playlists
    func deletePlaylists(ids: [Int64], completion: ((Result<Void, PlaylistError>) -> Void)? = nil) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            for id in ids {
                self.playlistDAO.delete(playlistId: id)
            }

            // Post notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.playlistsChanged,
                    object: nil,
                    userInfo: ["action": "deleted_multiple", "playlistIds": ids]
                )
            }

            self.callCompletion(completion, with: .success(()))
        }
    }

    // MARK: - Track Management

    /// Add a track to a playlist
    func addTrack(trackId: Int64, toPlaylist playlistId: Int64, completion: ((Result<Void, PlaylistError>) -> Void)? = nil) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.playlistDAO.getById(id: playlistId) != nil else {
                self.callCompletion(completion, with: .failure(.notFound))
                return
            }

            guard self.trackDAO.getById(id: trackId) != nil else {
                self.callCompletion(completion, with: .failure(.trackNotFound))
                return
            }

            self.playlistDAO.addTrack(playlistId: playlistId, trackId: trackId)

            // Post notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.playlistContentChanged,
                    object: nil,
                    userInfo: ["action": "track_added", "playlistId": playlistId, "trackId": trackId]
                )
            }

            self.callCompletion(completion, with: .success(()))
        }
    }

    /// Add multiple tracks to a playlist
    func addTracks(trackIds: [Int64], toPlaylist playlistId: Int64, completion: ((Result<Void, PlaylistError>) -> Void)? = nil) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.playlistDAO.getById(id: playlistId) != nil else {
                self.callCompletion(completion, with: .failure(.notFound))
                return
            }

            for trackId in trackIds {
                guard self.trackDAO.getById(id: trackId) != nil else {
                    continue // Skip tracks that don't exist
                }
                self.playlistDAO.addTrack(playlistId: playlistId, trackId: trackId)
            }

            // Post notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.playlistContentChanged,
                    object: nil,
                    userInfo: ["action": "tracks_added", "playlistId": playlistId, "trackIds": trackIds]
                )
            }

            self.callCompletion(completion, with: .success(()))
        }
    }

    /// Remove a track from a playlist
    func removeTrack(trackId: Int64, fromPlaylist playlistId: Int64, completion: ((Result<Void, PlaylistError>) -> Void)? = nil) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.playlistDAO.getById(id: playlistId) != nil else {
                self.callCompletion(completion, with: .failure(.notFound))
                return
            }

            self.playlistDAO.removeTrack(playlistId: playlistId, trackId: trackId)

            // Post notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.playlistContentChanged,
                    object: nil,
                    userInfo: ["action": "track_removed", "playlistId": playlistId, "trackId": trackId]
                )
            }

            self.callCompletion(completion, with: .success(()))
        }
    }

    /// Remove multiple tracks from a playlist
    func removeTracks(trackIds: [Int64], fromPlaylist playlistId: Int64, completion: ((Result<Void, PlaylistError>) -> Void)? = nil) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.playlistDAO.getById(id: playlistId) != nil else {
                self.callCompletion(completion, with: .failure(.notFound))
                return
            }

            for trackId in trackIds {
                self.playlistDAO.removeTrack(playlistId: playlistId, trackId: trackId)
            }

            // Post notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.playlistContentChanged,
                    object: nil,
                    userInfo: ["action": "tracks_removed", "playlistId": playlistId, "trackIds": trackIds]
                )
            }

            self.callCompletion(completion, with: .success(()))
        }
    }

    /// Get all tracks in a playlist
    func getTracks(forPlaylist playlistId: Int64, completion: @escaping (Result<[Track], PlaylistError>) -> Void) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.playlistDAO.getById(id: playlistId) != nil else {
                self.callCompletion(completion, with: .failure(.notFound))
                return
            }

            let tracks = self.playlistDAO.getTracksForPlaylist(playlistId: playlistId)
            self.callCompletion(completion, with: .success(tracks))
        }
    }

    /// Get tracks synchronously
    func getTracks(forPlaylist playlistId: Int64) -> [Track] {
        return playlistDAO.getTracksForPlaylist(playlistId: playlistId)
    }

    /// Reorder tracks in a playlist
    func reorderTracks(inPlaylist playlistId: Int64, trackIds: [Int64], completion: ((Result<Void, PlaylistError>) -> Void)? = nil) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.playlistDAO.getById(id: playlistId) != nil else {
                self.callCompletion(completion, with: .failure(.notFound))
                return
            }

            self.playlistDAO.reorderTracks(playlistId: playlistId, trackIds: trackIds)

            // Post notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.playlistContentChanged,
                    object: nil,
                    userInfo: ["action": "tracks_reordered", "playlistId": playlistId]
                )
            }

            self.callCompletion(completion, with: .success(()))
        }
    }

    /// Clear all tracks from a playlist
    func clearPlaylist(id: Int64, completion: ((Result<Void, PlaylistError>) -> Void)? = nil) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.playlistDAO.getById(id: id) != nil else {
                self.callCompletion(completion, with: .failure(.notFound))
                return
            }

            let tracks = self.playlistDAO.getTracksForPlaylist(playlistId: id)
            for track in tracks {
                self.playlistDAO.removeTrack(playlistId: id, trackId: track.id)
            }

            // Post notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.playlistContentChanged,
                    object: nil,
                    userInfo: ["action": "cleared", "playlistId": id]
                )
            }

            self.callCompletion(completion, with: .success(()))
        }
    }

    // MARK: - Utility Methods

    /// Check if a track exists in a playlist
    func isTrackInPlaylist(trackId: Int64, playlistId: Int64) -> Bool {
        let tracks = playlistDAO.getTracksForPlaylist(playlistId: playlistId)
        return tracks.contains(where: { $0.id == trackId })
    }

    /// Duplicate a playlist
    func duplicatePlaylist(id: Int64, newName: String? = nil, completion: ((Result<Playlist, PlaylistError>) -> Void)? = nil) {
        playlistQueue.async { [weak self] in
            guard let self = self else { return }

            guard let originalPlaylist = self.playlistDAO.getById(id: id) else {
                self.callCompletion(completion, with: .failure(.notFound))
                return
            }

            let duplicateName = newName ?? "\(originalPlaylist.name) Copy"

            // Create the duplicate playlist
            let now = Date()
            let newPlaylist = Playlist(
                id: 0,
                name: duplicateName,
                dateCreated: now,
                dateModified: now,
                isSmartPlaylist: originalPlaylist.isSmartPlaylist,
                smartCriteria: originalPlaylist.smartCriteria,
                trackCount: 0
            )

            let newPlaylistId = self.playlistDAO.insert(playlist: newPlaylist)

            // Copy tracks if not a smart playlist
            if !originalPlaylist.isSmartPlaylist {
                let tracks = self.playlistDAO.getTracksForPlaylist(playlistId: id)
                for track in tracks {
                    self.playlistDAO.addTrack(playlistId: newPlaylistId, trackId: track.id)
                }
            }

            guard let createdPlaylist = self.playlistDAO.getById(id: newPlaylistId) else {
                self.callCompletion(completion, with: .failure(.creationFailed))
                return
            }

            // Post notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.playlistsChanged,
                    object: nil,
                    userInfo: ["action": "duplicated", "playlistId": newPlaylistId, "originalId": id]
                )
            }

            self.callCompletion(completion, with: .success(createdPlaylist))
        }
    }

    // MARK: - Helper Methods

    private func callCompletion<T>(_ completion: ((Result<T, PlaylistError>) -> Void)?, with result: Result<T, PlaylistError>) {
        guard let completion = completion else { return }
        DispatchQueue.main.async {
            completion(result)
        }
    }
}

// MARK: - Errors

enum PlaylistError: Error, LocalizedError {
    case notFound
    case invalidName
    case duplicateName
    case creationFailed
    case trackNotFound
    case unknown

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Playlist not found"
        case .invalidName:
            return "Playlist name is invalid or empty"
        case .duplicateName:
            return "A playlist with this name already exists"
        case .creationFailed:
            return "Failed to create playlist"
        case .trackNotFound:
            return "Track not found"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
