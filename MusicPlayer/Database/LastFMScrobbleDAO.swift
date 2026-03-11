import Foundation

struct PendingScrobble {
    let id: Int64
    let trackTitle: String
    let artist: String
    let album: String?
    let timestamp: Date
}

class LastFMScrobbleDAO {
    private let db = DatabaseManager.shared

    func queueScrobble(trackTitle: String, artist: String, album: String?, timestamp: Date) {
        let sql = """
        INSERT INTO lastfm_scrobble_queue (track_title, artist, album, timestamp, created_at)
        VALUES (?, ?, ?, ?, ?)
        """
        db.execute(sql: sql, parameters: [
            trackTitle,
            artist,
            album as Any,
            timestamp.timeIntervalSince1970,
            Date().timeIntervalSince1970
        ])
    }

    func getPendingScrobbles(limit: Int = 50) -> [PendingScrobble] {
        let sql = "SELECT * FROM lastfm_scrobble_queue ORDER BY timestamp ASC LIMIT ?"
        let results = db.query(sql: sql, parameters: [limit])
        return results.compactMap { row in
            guard let id = row["id"] as? Int64,
                  let title = row["track_title"] as? String,
                  let artist = row["artist"] as? String,
                  let ts = row["timestamp"] as? Double else { return nil }
            return PendingScrobble(
                id: id,
                trackTitle: title,
                artist: artist,
                album: row["album"] as? String,
                timestamp: Date(timeIntervalSince1970: ts)
            )
        }
    }

    func deleteScrobble(id: Int64) {
        db.execute(sql: "DELETE FROM lastfm_scrobble_queue WHERE id = ?", parameters: [id])
    }

    func clearAll() {
        db.execute(sql: "DELETE FROM lastfm_scrobble_queue")
    }
}
