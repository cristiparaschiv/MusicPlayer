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

        return db.executeInsert(sql: sql, parameters: [
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
    }

    enum TrackOrderBy {
        case `default`
        case dateAddedDesc
        case title
        case artist
        case duration

        var sql: String {
            switch self {
            case .default:
                return "COALESCE(album_artist_name, artist_name) COLLATE NOCASE ASC, year ASC, album_title COLLATE NOCASE ASC, track_number ASC"
            case .dateAddedDesc:
                return "date_added DESC"
            case .title:
                return "title COLLATE NOCASE ASC"
            case .artist:
                return "artist_name COLLATE NOCASE ASC"
            case .duration:
                return "duration ASC"
            }
        }
    }

    func getAll(limit: Int? = nil, offset: Int = 0, orderBy: TrackOrderBy = .default) -> [Track] {
        var sql = "SELECT * FROM tracks ORDER BY \(orderBy.sql)"

        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }

        let results = db.query(sql: sql)
        return results.compactMap { rowToTrack($0) }
    }

    func getById(id: Int64) -> Track? {
        let sql = "SELECT * FROM tracks WHERE id = ?"
        let results = db.query(sql: sql, parameters: [id])
        return results.first.flatMap { rowToTrack($0) }
    }

    func getByFilePath(path: String) -> Track? {
        let sql = "SELECT * FROM tracks WHERE file_path = ?"
        let results = db.query(sql: sql, parameters: [path])
        return results.first.flatMap { rowToTrack($0) }
    }

    func getByAlbumId(albumId: Int64, orderBy: String = "disc_number, track_number, title_sort") -> [Track] {
        let sql = "SELECT * FROM tracks WHERE album_id = ? ORDER BY \(orderBy)"
        let results = db.query(sql: sql, parameters: [albumId])
        return results.compactMap { rowToTrack($0) }
    }

    func getByArtistId(artistId: Int64, limit: Int? = nil, offset: Int = 0) -> [Track] {
        var sql = "SELECT * FROM tracks WHERE artist_id = ? ORDER BY year DESC, album_title, track_number"
        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }

        let results = db.query(sql: sql, parameters: [artistId])
        return results.compactMap { rowToTrack($0) }
    }

    func getArtistTracksInfo(artistId: Int64) -> ArtistTracksInfo {
        let tracks = getByArtistId(artistId: artistId)
        return ArtistTracksInfo(tracks: tracks)
    }

    func getArtistTracksInfo(artistName: String) -> ArtistTracksInfo {
        let sql = "SELECT * FROM tracks WHERE artist_name = ? ORDER BY year DESC, album_title, track_number"
        let results = db.query(sql: sql, parameters: [artistName])
        let tracks = results.compactMap { rowToTrack($0) }
        return ArtistTracksInfo(tracks: tracks)
    }

    func search(query: String, limit: Int = 100) -> [Track] {
        // Escape FTS5 special characters and add prefix matching
        let sanitized = query
            .replacingOccurrences(of: "\"", with: "\"\"")
            .trimmingCharacters(in: .whitespaces)
        guard !sanitized.isEmpty else { return [] }

        // Try FTS5 first for fast matching
        let ftsSql = """
        SELECT t.* FROM tracks t
        INNER JOIN tracks_fts fts ON t.id = fts.rowid
        WHERE tracks_fts MATCH ?
        ORDER BY t.title_sort
        LIMIT ?
        """

        let ftsQuery = "\"\(sanitized)\"*"
        let results = db.query(sql: ftsSql, parameters: [ftsQuery, limit])
        if !results.isEmpty {
            return results.compactMap { rowToTrack($0) }
        }

        // Fallback to LIKE if FTS returns nothing (handles partial mid-word matches)
        let likeSql = """
        SELECT * FROM tracks
        WHERE title LIKE ? OR artist_name LIKE ? OR album_title LIKE ?
        ORDER BY title_sort
        LIMIT ?
        """
        let searchTerm = "%\(query)%"
        let likeResults = db.query(sql: likeSql, parameters: [searchTerm, searchTerm, searchTerm, limit])
        return likeResults.compactMap { rowToTrack($0) }
    }

    func getRecentlyAdded(limit: Int = 20) -> [Track] {
        let sql = "SELECT * FROM tracks ORDER BY date_added DESC LIMIT ?"
        let results = db.query(sql: sql, parameters: [limit])
        return results.compactMap { rowToTrack($0) }
    }

    func getRecentlyPlayed(limit: Int = 20) -> [Track] {
        let sql = "SELECT * FROM tracks WHERE last_played IS NOT NULL ORDER BY last_played DESC LIMIT ?"
        let results = db.query(sql: sql, parameters: [limit])
        return results.compactMap { rowToTrack($0) }
    }

    func getMostPlayed(limit: Int = 20) -> [Track] {
        let sql = "SELECT * FROM tracks WHERE play_count > 0 ORDER BY play_count DESC LIMIT ?"
        let results = db.query(sql: sql, parameters: [limit])
        return results.compactMap { rowToTrack($0) }
    }

    func getFavorites(limit: Int? = nil, offset: Int = 0) -> [Track] {
        var sql = "SELECT * FROM tracks WHERE is_favorite = 1 ORDER BY title_sort"
        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }

        let results = db.query(sql: sql)
        return results.compactMap { rowToTrack($0) }
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
        return results.first.flatMap { rowToTrack($0) }
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
                           file_size, date_added, date_modified, has_artwork, lyrics,
                           replay_gain_track, replay_gain_album, channel_count, format_name, bit_depth,
                           start_time, end_time)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            0, // has_artwork
            metadata.lyrics as Any,
            metadata.replayGainTrackGain as Any,
            metadata.replayGainAlbumGain as Any,
            metadata.channelCount as Any,
            metadata.formatName as Any,
            metadata.bitDepth as Any,
            metadata.startTime as Any,
            metadata.endTime as Any
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
            file_size = ?, date_modified = ?, lyrics = ?,
            replay_gain_track = ?, replay_gain_album = ?,
            channel_count = ?, format_name = ?, bit_depth = ?
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
            metadata.lyrics as Any,
            metadata.replayGainTrackGain as Any,
            metadata.replayGainAlbumGain as Any,
            metadata.channelCount as Any,
            metadata.formatName as Any,
            metadata.bitDepth as Any,
            filePath
        ])
    }

    // MARK: - Helper Methods for Creating Related Entities

    private func getOrCreateArtist(name: String) -> Int64 {
        // Check in-memory cache first
        if let cached = MediaScannerManager.shared.getCachedArtist(name) {
            return cached
        }

        // Check database
        let selectSql = "SELECT id FROM artists WHERE name = ?"
        let results = db.query(sql: selectSql, parameters: [name])
        if let row = results.first, let id = row["id"] as? Int64 {
            MediaScannerManager.shared.setCachedArtist(name, id: id)
            return id
        }

        // Create new artist
        let insertSql = """
        INSERT INTO artists (name, name_sort)
        VALUES (?, ?)
        """
        let id = db.executeInsert(sql: insertSql, parameters: [name, name.sortKey])
        MediaScannerManager.shared.setCachedArtist(name, id: id)
        return id
    }

    private func getOrCreateGenre(name: String) -> Int64 {
        if let cached = MediaScannerManager.shared.getCachedGenre(name) {
            return cached
        }

        let selectSql = "SELECT id FROM genres WHERE name = ?"
        let results = db.query(sql: selectSql, parameters: [name])
        if let row = results.first, let id = row["id"] as? Int64 {
            MediaScannerManager.shared.setCachedGenre(name, id: id)
            return id
        }

        let insertSql = "INSERT INTO genres (name) VALUES (?)"
        let id = db.executeInsert(sql: insertSql, parameters: [name])
        MediaScannerManager.shared.setCachedGenre(name, id: id)
        return id
    }

    private func getOrCreateComposer(name: String) -> Int64 {
        if let cached = MediaScannerManager.shared.getCachedComposer(name) {
            return cached
        }

        let selectSql = "SELECT id FROM composers WHERE name = ?"
        let results = db.query(sql: selectSql, parameters: [name])
        if let row = results.first, let id = row["id"] as? Int64 {
            MediaScannerManager.shared.setCachedComposer(name, id: id)
            return id
        }

        let insertSql = "INSERT INTO composers (name) VALUES (?)"
        let id = db.executeInsert(sql: insertSql, parameters: [name])
        MediaScannerManager.shared.setCachedComposer(name, id: id)
        return id
    }

    private func getOrCreateAlbum(
        title: String,
        artistId: Int64?,
        artistName: String?,
        year: Int?,
        genreId: Int64?,
        genreName: String?
    ) -> Int64 {
        let cacheKey = "\(title)|\(artistId ?? -1)"

        if let cached = MediaScannerManager.shared.getCachedAlbum(cacheKey) {
            return cached
        }

        // Check database
        let selectSql = "SELECT id FROM albums WHERE title = ? AND artist_id IS ?"
        let results = db.query(sql: selectSql, parameters: [title, artistId as Any])
        if let row = results.first, let id = row["id"] as? Int64 {
            MediaScannerManager.shared.setCachedAlbum(cacheKey, id: id)
            return id
        }

        // Create new album
        let insertSql = """
        INSERT INTO albums (title, title_sort, artist_id, artist_name, year, genre_id, genre_name, date_added)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        let id = db.executeInsert(sql: insertSql, parameters: [
            title,
            title.sortKey,
            artistId as Any,
            artistName as Any,
            year as Any,
            genreId as Any,
            genreName as Any,
            Date().timeIntervalSince1970
        ])
        MediaScannerManager.shared.setCachedAlbum(cacheKey, id: id)
        return id
    }

    func trackFromRow(_ row: [String: Any]) -> Track? {
        return rowToTrack(row)
    }

    private func rowToTrack(_ row: [String: Any]) -> Track? {
        guard let id = row["id"] as? Int64,
              let title = row["title"] as? String,
              let duration = row["duration"] as? Double,
              let filePath = row["file_path"] as? String,
              let fileSize = row["file_size"] as? Int64,
              let dateAdded = row["date_added"] as? Double,
              let dateModified = row["date_modified"] as? Double else {
            return nil
        }

        return Track(
            id: id,
            title: title,
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
            duration: duration,
            bitrate: (row["bitrate"] as? Int64).map { Int($0) },
            sampleRate: (row["sample_rate"] as? Int64).map { Int($0) },
            channelCount: (row["channel_count"] as? Int64).map { Int($0) },
            formatName: row["format_name"] as? String,
            bitDepth: (row["bit_depth"] as? Int64).map { Int($0) },
            filePath: filePath,
            fileSize: fileSize,
            dateAdded: Date(timeIntervalSince1970: dateAdded),
            dateModified: Date(timeIntervalSince1970: dateModified),
            lastPlayed: (row["last_played"] as? Double).map { Date(timeIntervalSince1970: $0) },
            playCount: Int(row["play_count"] as? Int64 ?? 0),
            rating: (row["rating"] as? Int64).map { Int($0) },
            isFavorite: (row["is_favorite"] as? Int64 ?? 0) == 1,
            hasArtwork: (row["has_artwork"] as? Int64 ?? 0) == 1,
            lyrics: row["lyrics"] as? String,
            replayGainTrackGain: row["replay_gain_track"] as? Double,
            replayGainAlbumGain: row["replay_gain_album"] as? Double,
            startTime: row["start_time"] as? Double,
            endTime: row["end_time"] as? Double
        )
    }
}
