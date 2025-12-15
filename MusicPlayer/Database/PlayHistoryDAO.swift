import Foundation

class PlayHistoryDAO {
    private let db = DatabaseManager.shared

    // MARK: - Record Play Events

    /// Record a new play event for a track
    func recordPlay(trackId: Int64) -> Int64 {
        let sql = """
        INSERT INTO play_history (track_id, played_at, completed)
        VALUES (?, ?, 0)
        """

        db.execute(sql: sql, parameters: [
            trackId,
            Date().timeIntervalSince1970
        ])

        return db.lastInsertRowId()
    }

    /// Mark a play event as completed (user finished >80% of track)
    func markCompleted(playId: Int64) {
        let sql = "UPDATE play_history SET completed = 1 WHERE id = ?"
        db.execute(sql: sql, parameters: [playId])
    }

    // MARK: - Query Methods

    /// Get recently played tracks (unique tracks, sorted by most recent play)
    func getRecentlyPlayed(limit: Int = 20) -> [Track] {
        let sql = """
        SELECT t.* FROM tracks t
        INNER JOIN (
            SELECT track_id, MAX(played_at) as last_played
            FROM play_history
            GROUP BY track_id
        ) ph ON t.id = ph.track_id
        ORDER BY ph.last_played DESC
        LIMIT ?
        """

        let results = db.query(sql: sql, parameters: [limit])
        return results.map { TrackDAO().trackFromRow($0) }
    }

    /// Get most frequently played tracks
    func getMostPlayed(limit: Int = 20) -> [Track] {
        let sql = """
        SELECT t.*, COUNT(ph.id) as play_count
        FROM tracks t
        INNER JOIN play_history ph ON t.id = ph.track_id
        GROUP BY t.id
        ORDER BY play_count DESC, MAX(ph.played_at) DESC
        LIMIT ?
        """

        let results = db.query(sql: sql, parameters: [limit])
        return results.map { TrackDAO().trackFromRow($0) }
    }

    /// Get total play count for a specific track
    func getPlayCount(trackId: Int64) -> Int {
        let sql = "SELECT COUNT(*) as count FROM play_history WHERE track_id = ?"
        let result = db.query(sql: sql, parameters: [trackId]).first
        return Int(result?["count"] as? Int64 ?? 0)
    }

    /// Get completed play count for a specific track
    func getCompletedPlayCount(trackId: Int64) -> Int {
        let sql = "SELECT COUNT(*) as count FROM play_history WHERE track_id = ? AND completed = 1"
        let result = db.query(sql: sql, parameters: [trackId]).first
        return Int(result?["count"] as? Int64 ?? 0)
    }

    /// Get play history for a specific track
    func getPlayHistory(trackId: Int64, limit: Int? = nil) -> [PlayHistoryEntry] {
        var sql = "SELECT * FROM play_history WHERE track_id = ? ORDER BY played_at DESC"

        var parameters: [Any] = [trackId]
        if let limit = limit {
            sql += " LIMIT ?"
            parameters.append(limit)
        }

        let results = db.query(sql: sql, parameters: parameters)
        return results.map { rowToPlayHistory($0) }
    }

    /// Delete play history older than a specific date
    func deleteOlderThan(date: Date) {
        let sql = "DELETE FROM play_history WHERE played_at < ?"
        db.execute(sql: sql, parameters: [date.timeIntervalSince1970])
    }

    /// Clear all play history
    func clearAll() {
        let sql = "DELETE FROM play_history"
        db.execute(sql: sql)
    }

    // MARK: - Helper Methods

    private func rowToPlayHistory(_ row: [String: Any]) -> PlayHistoryEntry {
        return PlayHistoryEntry(
            id: row["id"] as! Int64,
            trackId: row["track_id"] as! Int64,
            playedAt: Date(timeIntervalSince1970: row["played_at"] as! Double),
            completed: (row["completed"] as? Int64 ?? 0) == 1
        )
    }
}

// MARK: - Supporting Types

struct PlayHistoryEntry {
    let id: Int64
    let trackId: Int64
    let playedAt: Date
    let completed: Bool
}
