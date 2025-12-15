import Foundation

class ArtistDAO {
    private let db = DatabaseManager.shared

    func insert(artist: Artist) -> Int64 {
        let sql = """
        INSERT INTO artists (name, name_sort, album_count, track_count, profile_image_path)
        VALUES (?, ?, ?, ?, ?)
        """

        db.execute(sql: sql, parameters: [
            artist.name,
            artist.nameSort,
            artist.albumCount,
            artist.trackCount,
            artist.profileImagePath as Any
        ])

        return db.lastInsertRowId()
    }

    func getAll(limit: Int? = nil, offset: Int = 0, orderBy: String = "name_sort") -> [Artist] {
        var sql = "SELECT * FROM artists ORDER BY \(orderBy)"
        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }

        let results = db.query(sql: sql)
        return results.map { rowToArtist($0) }
    }

    func getById(id: Int64) -> Artist? {
        let sql = "SELECT * FROM artists WHERE id = ?"
        let results = db.query(sql: sql, parameters: [id])
        return results.first.map { rowToArtist($0) }
    }

    func search(query: String, limit: Int = 100) -> [Artist] {
        let sql = """
        SELECT * FROM artists
        WHERE name LIKE ?
        ORDER BY name_sort
        LIMIT ?
        """

        let searchTerm = "%\(query)%"
        print("[ArtistDAO] Searching with term: '\(searchTerm)'")
        let results = db.query(sql: sql, parameters: [searchTerm, limit])
        print("[ArtistDAO] Query returned \(results.count) rows")
        let artists = results.map { rowToArtist($0) }
        print("[ArtistDAO] Mapped to \(artists.count) artists")
        return artists
    }

    func getTopArtists(limit: Int = 20) -> [Artist] {
        let sql = "SELECT * FROM artists ORDER BY track_count DESC LIMIT ?"
        let results = db.query(sql: sql, parameters: [limit])
        return results.map { rowToArtist($0) }
    }

    func update(artist: Artist) {
        let sql = """
        UPDATE artists
        SET name = ?, name_sort = ?, album_count = ?, track_count = ?, profile_image_path = ?
        WHERE id = ?
        """

        db.execute(sql: sql, parameters: [
            artist.name,
            artist.nameSort,
            artist.albumCount,
            artist.trackCount,
            artist.profileImagePath as Any,
            artist.id
        ])
    }

    func delete(artistId: Int64) {
        let sql = "DELETE FROM artists WHERE id = ?"
        db.execute(sql: sql, parameters: [artistId])
    }

    func getCount() -> Int {
        let sql = "SELECT COUNT(*) as count FROM artists"
        let result = db.query(sql: sql).first
        return Int(result?["count"] as? Int64 ?? 0)
    }

    func getOrCreateByName(name: String) -> Int64 {
        let sql = "SELECT id FROM artists WHERE name = ?"
        let results = db.query(sql: sql, parameters: [name])

        if let existingId = results.first?["id"] as? Int64 {
            return existingId
        }

        let newArtist = Artist(id: 0, name: name)
        return insert(artist: newArtist)
    }

    func updateCounts(artistId: Int64) {
        let albumCountSQL = """
        UPDATE artists SET album_count = (
            SELECT COUNT(DISTINCT id) FROM albums WHERE artist_id = ?
        ) WHERE id = ?
        """

        let trackCountSQL = """
        UPDATE artists SET track_count = (
            SELECT COUNT(*) FROM tracks WHERE artist_id = ?
        ) WHERE id = ?
        """

        db.execute(sql: albumCountSQL, parameters: [artistId, artistId])
        db.execute(sql: trackCountSQL, parameters: [artistId, artistId])
    }

    private func rowToArtist(_ row: [String: Any]) -> Artist {
        return Artist(
            id: row["id"] as! Int64,
            name: row["name"] as! String,
            nameSort: row["name_sort"] as? String,
            albumCount: Int(row["album_count"] as? Int64 ?? 0),
            trackCount: Int(row["track_count"] as? Int64 ?? 0),
            profileImagePath: row["profile_image_path"] as? String
        )
    }
}
