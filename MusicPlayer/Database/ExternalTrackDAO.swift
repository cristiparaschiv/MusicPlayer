import Foundation

class ExternalTrackDAO {
    private let db = DatabaseManager.shared

    /// Insert a track into external_tracks and external_playlist_tracks.
    /// Returns the new track ID, or nil on failure.
    func insert(metadata: AudioMetadata) -> Int64? {
        let title = metadata.title ?? "Unknown"
        let titleSort = title.sortKey
        let now = Date().timeIntervalSince1970

        let sql = """
        INSERT INTO external_tracks (
            title, title_sort, artist_name, album_title, album_artist_name,
            track_number, disc_number, year, genre_name, composer_name,
            duration, bitrate, sample_rate, channel_count, bit_depth,
            format_name, file_path, file_size, date_added, has_artwork,
            lyrics, replay_gain_track, replay_gain_album
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        let trackId = db.executeInsert(sql: sql, parameters: [
            title,
            titleSort,
            metadata.artist as Any,
            metadata.album as Any,
            metadata.albumArtist as Any,
            metadata.trackNumber as Any,
            metadata.discNumber as Any,
            metadata.year as Any,
            metadata.genre as Any,
            metadata.composer as Any,
            metadata.duration,
            metadata.bitrate as Any,
            metadata.sampleRate as Any,
            metadata.channelCount as Any,
            metadata.bitDepth as Any,
            metadata.formatName as Any,
            metadata.filePath,
            metadata.fileSize,
            now,
            0, // has_artwork
            metadata.lyrics as Any,
            metadata.replayGainTrackGain as Any,
            metadata.replayGainAlbumGain as Any
        ])

        guard trackId > 0 else { return nil }

        // Get next position
        let posResult = db.query(sql: "SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM external_playlist_tracks")
        let position = Int(posResult.first?["next_pos"] as? Int64 ?? 0)

        db.execute(sql: """
            INSERT INTO external_playlist_tracks (track_id, position, date_added)
            VALUES (?, ?, ?)
        """, parameters: [trackId, position, now])

        return trackId
    }

    /// Returns all external tracks ordered by playlist position.
    func getAllTracks() -> [Track] {
        let sql = """
        SELECT et.* FROM external_tracks et
        INNER JOIN external_playlist_tracks ept ON et.id = ept.track_id
        ORDER BY ept.position
        """
        let results = db.query(sql: sql)
        return results.compactMap { rowToTrack($0) }
    }

    /// Returns the number of external tracks.
    func trackCount() -> Int {
        let result = db.query(sql: "SELECT COUNT(*) as count FROM external_tracks").first
        return Int(result?["count"] as? Int64 ?? 0)
    }

    /// Deletes all external tracks and playlist entries.
    func clearAll() {
        db.execute(sql: "DELETE FROM external_playlist_tracks")
        db.execute(sql: "DELETE FROM external_tracks")
    }

    /// Removes a single external track by ID.
    func removeTrack(id: Int64) {
        db.execute(sql: "DELETE FROM external_playlist_tracks WHERE track_id = ?", parameters: [id])
        db.execute(sql: "DELETE FROM external_tracks WHERE id = ?", parameters: [id])
    }

    // MARK: - Row Mapping

    private func rowToTrack(_ row: [String: Any]) -> Track? {
        guard let id = row["id"] as? Int64,
              let title = row["title"] as? String,
              let duration = row["duration"] as? Double,
              let filePath = row["file_path"] as? String,
              let fileSize = row["file_size"] as? Int64,
              let dateAdded = row["date_added"] as? Double else {
            return nil
        }

        let addedDate = Date(timeIntervalSince1970: dateAdded)

        return Track(
            id: id,
            title: title,
            titleSort: row["title_sort"] as? String,
            artistId: nil,
            artistName: row["artist_name"] as? String,
            albumId: nil,
            albumTitle: row["album_title"] as? String,
            albumArtistName: row["album_artist_name"] as? String,
            trackNumber: (row["track_number"] as? Int64).map { Int($0) },
            discNumber: (row["disc_number"] as? Int64).map { Int($0) },
            year: (row["year"] as? Int64).map { Int($0) },
            genreId: nil,
            genreName: row["genre_name"] as? String,
            composerId: nil,
            composerName: row["composer_name"] as? String,
            duration: duration,
            bitrate: (row["bitrate"] as? Int64).map { Int($0) },
            sampleRate: (row["sample_rate"] as? Int64).map { Int($0) },
            channelCount: (row["channel_count"] as? Int64).map { Int($0) },
            formatName: row["format_name"] as? String,
            bitDepth: (row["bit_depth"] as? Int64).map { Int($0) },
            filePath: filePath,
            fileSize: fileSize,
            dateAdded: addedDate,
            dateModified: addedDate,
            lastPlayed: nil,
            playCount: 0,
            rating: nil,
            isFavorite: false,
            hasArtwork: (row["has_artwork"] as? Int64 ?? 0) == 1,
            lyrics: row["lyrics"] as? String,
            replayGainTrackGain: row["replay_gain_track"] as? Double,
            replayGainAlbumGain: row["replay_gain_album"] as? Double,
            startTime: nil,
            endTime: nil
        )
    }
}
