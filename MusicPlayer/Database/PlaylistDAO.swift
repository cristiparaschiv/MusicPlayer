import Foundation

class PlaylistDAO {
    private let db = DatabaseManager.shared

    func insert(playlist: Playlist) -> Int64 {
        let sql = """
        INSERT INTO playlists (name, date_created, date_modified, is_smart_playlist, smart_criteria, track_count)
        VALUES (?, ?, ?, ?, ?, ?)
        """

        db.execute(sql: sql, parameters: [
            playlist.name,
            playlist.dateCreated.timeIntervalSince1970,
            playlist.dateModified.timeIntervalSince1970,
            playlist.isSmartPlaylist,
            playlist.smartCriteria as Any,
            playlist.trackCount
        ])

        return db.lastInsertRowId()
    }

    func getAll() -> [Playlist] {
        let sql = "SELECT * FROM playlists ORDER BY name"
        let results = db.query(sql: sql)
        return results.map { rowToPlaylist($0) }
    }

    func getById(id: Int64) -> Playlist? {
        let sql = "SELECT * FROM playlists WHERE id = ?"
        let results = db.query(sql: sql, parameters: [id])
        return results.first.map { rowToPlaylist($0) }
    }

    func update(playlist: Playlist) {
        let sql = """
        UPDATE playlists
        SET name = ?, date_modified = ?, is_smart_playlist = ?, smart_criteria = ?, track_count = ?
        WHERE id = ?
        """

        db.execute(sql: sql, parameters: [
            playlist.name,
            Date().timeIntervalSince1970,
            playlist.isSmartPlaylist,
            playlist.smartCriteria as Any,
            playlist.trackCount,
            playlist.id
        ])
    }

    func delete(playlistId: Int64) {
        let sql = "DELETE FROM playlists WHERE id = ?"
        db.execute(sql: sql, parameters: [playlistId])
    }

    func addTrack(playlistId: Int64, trackId: Int64) {
        let positionSQL = "SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?"
        let positionResult = db.query(sql: positionSQL, parameters: [playlistId])
        let position = Int(positionResult.first?["next_pos"] as? Int64 ?? 0)

        let sql = """
        INSERT INTO playlist_tracks (playlist_id, track_id, position, date_added)
        VALUES (?, ?, ?, ?)
        """

        db.execute(sql: sql, parameters: [
            playlistId,
            trackId,
            position,
            Date().timeIntervalSince1970
        ])

        updateTrackCount(playlistId: playlistId)
    }

    func removeTrack(playlistId: Int64, trackId: Int64) {
        let sql = "DELETE FROM playlist_tracks WHERE playlist_id = ? AND track_id = ?"
        db.execute(sql: sql, parameters: [playlistId, trackId])
        updateTrackCount(playlistId: playlistId)
    }

    func clearPlaylist(playlistId: Int64) {
        let sql = "DELETE FROM playlist_tracks WHERE playlist_id = ?"
        db.execute(sql: sql, parameters: [playlistId])
        updateTrackCount(playlistId: playlistId)
    }

    func getTracksForPlaylist(playlistId: Int64) -> [Track] {
        let sql = """
        SELECT t.* FROM tracks t
        INNER JOIN playlist_tracks pt ON t.id = pt.track_id
        WHERE pt.playlist_id = ?
        ORDER BY pt.position
        """

        let results = db.query(sql: sql, parameters: [playlistId])
        let trackDAO = TrackDAO()
        return results.map { trackDAO.trackFromRow($0) }
    }

    func reorderTracks(playlistId: Int64, trackIds: [Int64]) {
        for (index, trackId) in trackIds.enumerated() {
            let sql = "UPDATE playlist_tracks SET position = ? WHERE playlist_id = ? AND track_id = ?"
            db.execute(sql: sql, parameters: [index, playlistId, trackId])
        }
    }

    private func updateTrackCount(playlistId: Int64) {
        let sql = """
        UPDATE playlists SET track_count = (
            SELECT COUNT(*) FROM playlist_tracks WHERE playlist_id = ?
        ) WHERE id = ?
        """

        db.execute(sql: sql, parameters: [playlistId, playlistId])
    }

    private func rowToPlaylist(_ row: [String: Any]) -> Playlist {
        return Playlist(
            id: row["id"] as! Int64,
            name: row["name"] as! String,
            dateCreated: Date(timeIntervalSince1970: row["date_created"] as! Double),
            dateModified: Date(timeIntervalSince1970: row["date_modified"] as! Double),
            isSmartPlaylist: (row["is_smart_playlist"] as? Int64 ?? 0) == 1,
            smartCriteria: row["smart_criteria"] as? String,
            trackCount: Int(row["track_count"] as? Int64 ?? 0)
        )
    }
}
