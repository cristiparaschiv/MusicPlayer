import Foundation

// MARK: - Supporting Types

struct ArtistTracksInfo {
    let tracks: [Track]
    let totalDuration: TimeInterval
    let formattedDuration: String
    let trackCount: Int

    init(tracks: [Track]) {
        self.tracks = tracks
        self.trackCount = tracks.count
        self.totalDuration = tracks.reduce(0) { $0 + $1.duration }
        self.formattedDuration = totalDuration.formattedDuration
    }
}

class TrackDAO {
    private let db = DatabaseManager.shared

    func insert(track: Track) -> Int64 {
        let sql = """
        INSERT INTO tracks (title, title_sort, artist_id, artist_name, album_id, album_title,
                           album_artist_name, track_number, disc_number, year, genre_id, genre_name,
                           composer_id, composer_name, duration, bitrate, sample_rate, file_path,
                           file_size, date_added, date_modified, has_artwork)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        db.execute(sql: sql, parameters: [
            track.title,
            track.titleSort,
            track.artistId as Any,
            track.artistName as Any,
            track.albumId as Any,
            track.albumTitle as Any,
            track.albumArtistName as Any,
            track.trackNumber as Any,
            track.discNumber as Any,
            track.year as Any,
            track.genreId as Any,
            track.genreName as Any,
            track.composerId as Any,
            track.composerName as Any,
            track.duration,
            track.bitrate as Any,
            track.sampleRate as Any,
            track.filePath,
            track.fileSize,
            track.dateAdded.timeIntervalSince1970,
            track.dateModified.timeIntervalSince1970,
            track.hasArtwork
        ])

        return db.lastInsertRowId()
    }

    func getAll(limit: Int? = nil, offset: Int = 0, orderBy: String? = nil) -> [Track] {
        var sql = "SELECT * FROM tracks"

        if let orderBy = orderBy {
            sql += " ORDER BY \(orderBy)"
        } else {
            // Default sort: artist alphabetically, albums chronologically (by year), tracks by track number
            sql += " ORDER BY COALESCE(album_artist_name, artist_name) COLLATE NOCASE ASC, year ASC, album_title COLLATE NOCASE ASC, track_number ASC"
        }

        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }

        let results = db.query(sql: sql)
        return results.map { rowToTrack($0) }
    }

    func getById(id: Int64) -> Track? {
        let sql = "SELECT * FROM tracks WHERE id = ?"
        let results = db.query(sql: sql, parameters: [id])
        return results.first.map { rowToTrack($0) }
    }

    func getByAlbumId(albumId: Int64, orderBy: String = "disc_number, track_number, title_sort") -> [Track] {
        let sql = "SELECT * FROM tracks WHERE album_id = ? ORDER BY \(orderBy)"
        let results = db.query(sql: sql, parameters: [albumId])
        return results.map { rowToTrack($0) }
    }

    func getByArtistId(artistId: Int64, limit: Int? = nil, offset: Int = 0) -> [Track] {
        var sql = "SELECT * FROM tracks WHERE artist_id = ? ORDER BY year DESC, album_title, track_number"
        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }

        let results = db.query(sql: sql, parameters: [artistId])
        return results.map { rowToTrack($0) }
    }

    func getArtistTracksInfo(artistId: Int64) -> ArtistTracksInfo {
        let tracks = getByArtistId(artistId: artistId)
        return ArtistTracksInfo(tracks: tracks)
    }

    func getArtistTracksInfo(artistName: String) -> ArtistTracksInfo {
        let sql = "SELECT * FROM tracks WHERE artist_name = ? ORDER BY year DESC, album_title, track_number"
        let results = db.query(sql: sql, parameters: [artistName])
        let tracks = results.map { rowToTrack($0) }
        return ArtistTracksInfo(tracks: tracks)
    }

    func search(query: String, limit: Int = 100) -> [Track] {
        let sql = """
        SELECT * FROM tracks
        WHERE title LIKE ? OR artist_name LIKE ? OR album_title LIKE ?
        ORDER BY title_sort
        LIMIT ?
        """

        let searchTerm = "%\(query)%"
        print("[TrackDAO] Searching with term: '\(searchTerm)'")
        let results = db.query(sql: sql, parameters: [searchTerm, searchTerm, searchTerm, limit])
        print("[TrackDAO] Query returned \(results.count) rows")
        let tracks = results.map { rowToTrack($0) }
        print("[TrackDAO] Mapped to \(tracks.count) tracks")
        return tracks
    }

    func getRecentlyAdded(limit: Int = 20) -> [Track] {
        let sql = "SELECT * FROM tracks ORDER BY date_added DESC LIMIT ?"
        let results = db.query(sql: sql, parameters: [limit])
        return results.map { rowToTrack($0) }
    }

    func getRecentlyPlayed(limit: Int = 20) -> [Track] {
        let sql = "SELECT * FROM tracks WHERE last_played IS NOT NULL ORDER BY last_played DESC LIMIT ?"
        let results = db.query(sql: sql, parameters: [limit])
        return results.map { rowToTrack($0) }
    }

    func getMostPlayed(limit: Int = 20) -> [Track] {
        let sql = "SELECT * FROM tracks WHERE play_count > 0 ORDER BY play_count DESC LIMIT ?"
        let results = db.query(sql: sql, parameters: [limit])
        return results.map { rowToTrack($0) }
    }

    func getFavorites(limit: Int? = nil, offset: Int = 0) -> [Track] {
        var sql = "SELECT * FROM tracks WHERE is_favorite = 1 ORDER BY title_sort"
        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }

        let results = db.query(sql: sql)
        return results.map { rowToTrack($0) }
    }

    func updatePlayCount(trackId: Int64) {
        let sql = "UPDATE tracks SET play_count = play_count + 1, last_played = ? WHERE id = ?"
        db.execute(sql: sql, parameters: [Date().timeIntervalSince1970, trackId])
    }

    func updateFavorite(trackId: Int64, isFavorite: Bool) {
        let sql = "UPDATE tracks SET is_favorite = ? WHERE id = ?"
        db.execute(sql: sql, parameters: [isFavorite, trackId])
    }

    func updateRating(trackId: Int64, rating: Int?) {
        let sql = "UPDATE tracks SET rating = ? WHERE id = ?"
        db.execute(sql: sql, parameters: [rating as Any, trackId])
    }

    func delete(trackId: Int64) {
        let sql = "DELETE FROM tracks WHERE id = ?"
        db.execute(sql: sql, parameters: [trackId])
    }

    func deleteTrack(id: Int64) {
        delete(trackId: id)
    }

    func getCount() -> Int {
        let sql = "SELECT COUNT(*) as count FROM tracks"
        let result = db.query(sql: sql).first
        return Int(result?["count"] as? Int64 ?? 0)
    }

    // MARK: - Scanner Support Methods

    func getTrack(byPath filePath: String) -> Track? {
        let sql = "SELECT * FROM tracks WHERE file_path = ?"
        let results = db.query(sql: sql, parameters: [filePath])
        return results.first.map { rowToTrack($0) }
    }

    func insertTrack(metadata: AudioMetadata) {
        // Get or create artist
        var artistId: Int64?
        var artistName: String?
        if let artist = metadata.albumArtist ?? metadata.artist {
            artistId = getOrCreateArtist(name: artist)
            artistName = artist
        }

        // Get or create genre
        var genreId: Int64?
        if let genre = metadata.genre {
            genreId = getOrCreateGenre(name: genre)
        }

        // Get or create composer
        var composerId: Int64?
        if let composer = metadata.composer {
            composerId = getOrCreateComposer(name: composer)
        }

        // Get or create album
        var albumId: Int64?
        var albumTitle: String?
        if let album = metadata.album {
            albumId = getOrCreateAlbum(
                title: album,
                artistId: artistId,
                artistName: artistName,
                year: metadata.year,
                genreId: genreId,
                genreName: metadata.genre
            )
            albumTitle = album
        }

        // Insert track
        let sql = """
        INSERT INTO tracks (title, title_sort, artist_id, artist_name, album_id, album_title,
                           album_artist_name, track_number, disc_number, year, genre_id, genre_name,
                           composer_id, composer_name, duration, bitrate, sample_rate, file_path,
                           file_size, date_added, date_modified, has_artwork)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        let title = metadata.title ?? "Unknown"
        let titleSort = title.sortKey

        db.execute(sql: sql, parameters: [
            title,
            titleSort,
            artistId as Any,
            artistName as Any,
            albumId as Any,
            albumTitle as Any,
            metadata.albumArtist as Any,
            metadata.trackNumber as Any,
            metadata.discNumber as Any,
            metadata.year as Any,
            genreId as Any,
            metadata.genre as Any,
            composerId as Any,
            metadata.composer as Any,
            metadata.duration,
            metadata.bitrate as Any,
            metadata.sampleRate as Any,
            metadata.filePath,
            metadata.fileSize,
            Date().timeIntervalSince1970,
            metadata.dateModified.timeIntervalSince1970,
            0 // has_artwork
        ])
    }

    func updateTrack(metadata: AudioMetadata, filePath: String) {
        // Get or create artist
        var artistId: Int64?
        var artistName: String?
        if let artist = metadata.albumArtist ?? metadata.artist {
            artistId = getOrCreateArtist(name: artist)
            artistName = artist
        }

        // Get or create genre
        var genreId: Int64?
        if let genre = metadata.genre {
            genreId = getOrCreateGenre(name: genre)
        }

        // Get or create composer
        var composerId: Int64?
        if let composer = metadata.composer {
            composerId = getOrCreateComposer(name: composer)
        }

        // Get or create album
        var albumId: Int64?
        var albumTitle: String?
        if let album = metadata.album {
            albumId = getOrCreateAlbum(
                title: album,
                artistId: artistId,
                artistName: artistName,
                year: metadata.year,
                genreId: genreId,
                genreName: metadata.genre
            )
            albumTitle = album
        }

        // Update track
        let sql = """
        UPDATE tracks SET
            title = ?, title_sort = ?, artist_id = ?, artist_name = ?,
            album_id = ?, album_title = ?, album_artist_name = ?,
            track_number = ?, disc_number = ?, year = ?,
            genre_id = ?, genre_name = ?, composer_id = ?, composer_name = ?,
            duration = ?, bitrate = ?, sample_rate = ?,
            file_size = ?, date_modified = ?
        WHERE file_path = ?
        """

        let title = metadata.title ?? "Unknown"
        let titleSort = title.sortKey

        db.execute(sql: sql, parameters: [
            title,
            titleSort,
            artistId as Any,
            artistName as Any,
            albumId as Any,
            albumTitle as Any,
            metadata.albumArtist as Any,
            metadata.trackNumber as Any,
            metadata.discNumber as Any,
            metadata.year as Any,
            genreId as Any,
            metadata.genre as Any,
            composerId as Any,
            metadata.composer as Any,
            metadata.duration,
            metadata.bitrate as Any,
            metadata.sampleRate as Any,
            metadata.fileSize,
            metadata.dateModified.timeIntervalSince1970,
            filePath
        ])
    }

    // MARK: - Helper Methods for Creating Related Entities

    private func getOrCreateArtist(name: String) -> Int64 {
        // Check if artist exists
        let selectSql = "SELECT id FROM artists WHERE name = ?"
        let results = db.query(sql: selectSql, parameters: [name])
        if let row = results.first, let id = row["id"] as? Int64 {
            return id
        }

        // Create new artist
        let insertSql = """
        INSERT INTO artists (name, name_sort)
        VALUES (?, ?)
        """
        db.execute(sql: insertSql, parameters: [name, name.sortKey])
        return db.lastInsertRowId()
    }

    private func getOrCreateGenre(name: String) -> Int64 {
        let selectSql = "SELECT id FROM genres WHERE name = ?"
        let results = db.query(sql: selectSql, parameters: [name])
        if let row = results.first, let id = row["id"] as? Int64 {
            return id
        }

        let insertSql = "INSERT INTO genres (name) VALUES (?)"
        db.execute(sql: insertSql, parameters: [name])
        return db.lastInsertRowId()
    }

    private func getOrCreateComposer(name: String) -> Int64 {
        let selectSql = "SELECT id FROM composers WHERE name = ?"
        let results = db.query(sql: selectSql, parameters: [name])
        if let row = results.first, let id = row["id"] as? Int64 {
            return id
        }

        let insertSql = "INSERT INTO composers (name) VALUES (?)"
        db.execute(sql: insertSql, parameters: [name])
        return db.lastInsertRowId()
    }

    private func getOrCreateAlbum(
        title: String,
        artistId: Int64?,
        artistName: String?,
        year: Int?,
        genreId: Int64?,
        genreName: String?
    ) -> Int64 {
        // Check if album exists (match by title and artist)
        let selectSql = "SELECT id FROM albums WHERE title = ? AND artist_id IS ?"
        let results = db.query(sql: selectSql, parameters: [title, artistId as Any])
        if let row = results.first, let id = row["id"] as? Int64 {
            return id
        }

        // Create new album
        let insertSql = """
        INSERT INTO albums (title, title_sort, artist_id, artist_name, year, genre_id, genre_name, date_added)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        db.execute(sql: insertSql, parameters: [
            title,
            title.sortKey,
            artistId as Any,
            artistName as Any,
            year as Any,
            genreId as Any,
            genreName as Any,
            Date().timeIntervalSince1970
        ])
        return db.lastInsertRowId()
    }

    func trackFromRow(_ row: [String: Any]) -> Track {
        return rowToTrack(row)
    }

    private func rowToTrack(_ row: [String: Any]) -> Track {
        return Track(
            id: row["id"] as! Int64,
            title: row["title"] as! String,
            titleSort: row["title_sort"] as? String,
            artistId: row["artist_id"] as? Int64,
            artistName: row["artist_name"] as? String,
            albumId: row["album_id"] as? Int64,
            albumTitle: row["album_title"] as? String,
            albumArtistName: row["album_artist_name"] as? String,
            trackNumber: (row["track_number"] as? Int64).map { Int($0) },
            discNumber: (row["disc_number"] as? Int64).map { Int($0) },
            year: (row["year"] as? Int64).map { Int($0) },
            genreId: row["genre_id"] as? Int64,
            genreName: row["genre_name"] as? String,
            composerId: row["composer_id"] as? Int64,
            composerName: row["composer_name"] as? String,
            duration: row["duration"] as! Double,
            bitrate: (row["bitrate"] as? Int64).map { Int($0) },
            sampleRate: (row["sample_rate"] as? Int64).map { Int($0) },
            filePath: row["file_path"] as! String,
            fileSize: row["file_size"] as! Int64,
            dateAdded: Date(timeIntervalSince1970: row["date_added"] as! Double),
            dateModified: Date(timeIntervalSince1970: row["date_modified"] as! Double),
            lastPlayed: (row["last_played"] as? Double).map { Date(timeIntervalSince1970: $0) },
            playCount: Int(row["play_count"] as? Int64 ?? 0),
            rating: (row["rating"] as? Int64).map { Int($0) },
            isFavorite: (row["is_favorite"] as? Int64 ?? 0) == 1,
            hasArtwork: (row["has_artwork"] as? Int64 ?? 0) == 1
        )
    }
}
