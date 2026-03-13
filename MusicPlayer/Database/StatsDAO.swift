import Foundation

struct ArtistStats {
    let name: String
    let playCount: Int
    let totalDuration: TimeInterval
}

struct AlbumStats {
    let title: String
    let artistName: String?
    let albumId: Int64
    let playCount: Int
}

struct GenreStats {
    let name: String
    let playCount: Int
}

struct DailyPlayCount {
    let date: Date
    let count: Int
}

class StatsDAO {
    private let db = DatabaseManager.shared

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Overview

    func getTotalTracks() -> Int {
        let result = db.query(sql: "SELECT COUNT(*) as count FROM tracks").first
        return Int(result?["count"] as? Int64 ?? 0)
    }

    func getTotalListeningTime(since: Date? = nil) -> TimeInterval {
        var sql = """
        SELECT SUM(t.duration) as total FROM play_history ph
        JOIN tracks t ON ph.track_id = t.id
        WHERE ph.completed = 1
        """
        var params: [Any] = []
        if let since = since {
            sql += " AND ph.played_at >= ?"
            params.append(since.timeIntervalSince1970)
        }
        let result = db.query(sql: sql, parameters: params).first
        return result?["total"] as? Double ?? 0
    }

    func getTracksPlayedCount(since: Date? = nil) -> Int {
        var sql = "SELECT COUNT(*) as count FROM play_history WHERE completed = 1"
        var params: [Any] = []
        if let since = since {
            sql += " AND played_at >= ?"
            params.append(since.timeIntervalSince1970)
        }
        let result = db.query(sql: sql, parameters: params).first
        return Int(result?["count"] as? Int64 ?? 0)
    }

    // MARK: - Top Artists

    func getTopArtists(since: Date? = nil, limit: Int = 10) -> [ArtistStats] {
        var sql = """
        SELECT t.artist_name, COUNT(*) as plays, SUM(t.duration) as total_time
        FROM play_history ph JOIN tracks t ON ph.track_id = t.id
        WHERE ph.completed = 1 AND t.artist_name IS NOT NULL
        """
        var params: [Any] = []
        if let since = since {
            sql += " AND ph.played_at >= ?"
            params.append(since.timeIntervalSince1970)
        }
        sql += " GROUP BY t.artist_name ORDER BY plays DESC LIMIT ?"
        params.append(limit)

        return db.query(sql: sql, parameters: params).compactMap { row in
            guard let name = row["artist_name"] as? String else { return nil }
            return ArtistStats(
                name: name,
                playCount: Int(row["plays"] as? Int64 ?? 0),
                totalDuration: row["total_time"] as? Double ?? 0
            )
        }
    }

    // MARK: - Top Albums

    func getTopAlbums(since: Date? = nil, limit: Int = 10) -> [AlbumStats] {
        var sql = """
        SELECT t.album_title, t.artist_name, t.album_id, COUNT(*) as plays
        FROM play_history ph JOIN tracks t ON ph.track_id = t.id
        WHERE ph.completed = 1 AND t.album_title IS NOT NULL
        """
        var params: [Any] = []
        if let since = since {
            sql += " AND ph.played_at >= ?"
            params.append(since.timeIntervalSince1970)
        }
        sql += " GROUP BY t.album_id ORDER BY plays DESC LIMIT ?"
        params.append(limit)

        return db.query(sql: sql, parameters: params).compactMap { row in
            guard let title = row["album_title"] as? String,
                  let albumId = row["album_id"] as? Int64 else { return nil }
            return AlbumStats(
                title: title,
                artistName: row["artist_name"] as? String,
                albumId: albumId,
                playCount: Int(row["plays"] as? Int64 ?? 0)
            )
        }
    }

    // MARK: - Top Genres

    func getTopGenres(since: Date? = nil, limit: Int = 10) -> [GenreStats] {
        var sql = """
        SELECT t.genre_name, COUNT(*) as plays
        FROM play_history ph JOIN tracks t ON ph.track_id = t.id
        WHERE ph.completed = 1 AND t.genre_name IS NOT NULL
        """
        var params: [Any] = []
        if let since = since {
            sql += " AND ph.played_at >= ?"
            params.append(since.timeIntervalSince1970)
        }
        sql += " GROUP BY t.genre_name ORDER BY plays DESC LIMIT ?"
        params.append(limit)

        return db.query(sql: sql, parameters: params).compactMap { row in
            guard let name = row["genre_name"] as? String else { return nil }
            return GenreStats(
                name: name,
                playCount: Int(row["plays"] as? Int64 ?? 0)
            )
        }
    }

    // MARK: - Daily Play Activity

    func getDailyPlayCounts(since: Date) -> [DailyPlayCount] {
        let sql = """
        SELECT date(played_at, 'unixepoch', 'localtime') as play_date, COUNT(*) as count
        FROM play_history
        WHERE completed = 1 AND played_at >= ?
        GROUP BY play_date
        ORDER BY play_date ASC
        """

        return db.query(sql: sql, parameters: [since.timeIntervalSince1970]).compactMap { row in
            guard let dateStr = row["play_date"] as? String,
                  let count = row["count"] as? Int64 else { return nil }
            guard let date = Self.dayFormatter.date(from: dateStr) else { return nil }
            return DailyPlayCount(date: date, count: Int(count))
        }
    }
}
