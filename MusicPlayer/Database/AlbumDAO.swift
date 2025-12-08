import Foundation

class AlbumDAO {
    private let db = DatabaseManager.shared

    func insert(album: Album) -> Int64 {
        let sql = """
        INSERT INTO albums (title, title_sort, artist_id, artist_name, year, genre_id, genre_name,
                           track_count, total_duration, date_added, artwork_path)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        db.execute(sql: sql, parameters: [
            album.title,
            album.titleSort,
            album.artistId as Any,
            album.artistName as Any,
            album.year as Any,
            album.genreId as Any,
            album.genreName as Any,
            album.trackCount,
            album.totalDuration,
            album.dateAdded.timeIntervalSince1970,
            album.artworkPath as Any
        ])

        return db.lastInsertRowId()
    }

    func getAll(limit: Int? = nil, offset: Int = 0, orderBy: String = "title_sort") -> [Album] {
        var sql = "SELECT * FROM albums ORDER BY \(orderBy)"
        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }

        let results = db.query(sql: sql)
        return results.map { rowToAlbum($0) }
    }

    func getById(id: Int64) -> Album? {
        let sql = "SELECT * FROM albums WHERE id = ?"
        let results = db.query(sql: sql, parameters: [id])
        return results.first.map { rowToAlbum($0) }
    }

    func getByArtistId(artistId: Int64, orderBy: String = "year DESC, title_sort") -> [Album] {
        let sql = "SELECT * FROM albums WHERE artist_id = ? ORDER BY \(orderBy)"
        let results = db.query(sql: sql, parameters: [artistId])
        return results.map { rowToAlbum($0) }
    }

    func search(query: String, limit: Int = 100) -> [Album] {
        let sql = """
        SELECT * FROM albums
        WHERE title LIKE ? OR artist_name LIKE ?
        ORDER BY title_sort
        LIMIT ?
        """

        let searchTerm = "%\(query)%"
        let results = db.query(sql: sql, parameters: [searchTerm, searchTerm, limit])
        return results.map { rowToAlbum($0) }
    }

    func getRecentlyAdded(limit: Int = 20) -> [Album] {
        let sql = "SELECT * FROM albums ORDER BY date_added DESC LIMIT ?"
        let results = db.query(sql: sql, parameters: [limit])
        return results.map { rowToAlbum($0) }
    }

    func getByYear(year: Int, limit: Int? = nil, offset: Int = 0) -> [Album] {
        var sql = "SELECT * FROM albums WHERE year = ? ORDER BY title_sort"
        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }

        let results = db.query(sql: sql, parameters: [year])
        return results.map { rowToAlbum($0) }
    }

    func update(album: Album) {
        let sql = """
        UPDATE albums
        SET title = ?, title_sort = ?, artist_id = ?, artist_name = ?, year = ?,
            genre_id = ?, genre_name = ?, track_count = ?, total_duration = ?, artwork_path = ?
        WHERE id = ?
        """

        db.execute(sql: sql, parameters: [
            album.title,
            album.titleSort,
            album.artistId as Any,
            album.artistName as Any,
            album.year as Any,
            album.genreId as Any,
            album.genreName as Any,
            album.trackCount,
            album.totalDuration,
            album.artworkPath as Any,
            album.id
        ])
    }

    func delete(albumId: Int64) {
        let sql = "DELETE FROM albums WHERE id = ?"
        db.execute(sql: sql, parameters: [albumId])
    }

    func getCount() -> Int {
        let sql = "SELECT COUNT(*) as count FROM albums"
        let result = db.query(sql: sql).first
        return Int(result?["count"] as? Int64 ?? 0)
    }

    func getOrCreateByTitleAndArtist(title: String, artistName: String?) -> Int64 {
        let sql = """
        SELECT id FROM albums WHERE title = ? AND artist_name = ?
        """

        let results = db.query(sql: sql, parameters: [title, artistName as Any])
        if let existingId = results.first?["id"] as? Int64 {
            return existingId
        }

        let newAlbum = Album(
            id: 0,
            title: title,
            artistName: artistName
        )

        return insert(album: newAlbum)
    }

    private func rowToAlbum(_ row: [String: Any]) -> Album {
        return Album(
            id: row["id"] as! Int64,
            title: row["title"] as! String,
            titleSort: row["title_sort"] as? String,
            artistId: row["artist_id"] as? Int64,
            artistName: row["artist_name"] as? String,
            year: (row["year"] as? Int64).map { Int($0) },
            genreId: row["genre_id"] as? Int64,
            genreName: row["genre_name"] as? String,
            trackCount: Int(row["track_count"] as? Int64 ?? 0),
            totalDuration: row["total_duration"] as? Double ?? 0,
            dateAdded: Date(timeIntervalSince1970: row["date_added"] as! Double),
            artworkPath: row["artwork_path"] as? String
        )
    }
}
