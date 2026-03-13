import Foundation

class PlaylistDAO {
    private let db = DatabaseManager.shared

    func insert(playlist: Playlist) -> Int64 {
        let sql = """
        INSERT INTO playlists (name, date_created, date_modified, is_smart_playlist, smart_criteria, track_count)
        VALUES (?, ?, ?, ?, ?, ?)
        """

        return db.executeInsert(sql: sql, parameters: [
            playlist.name,
            playlist.dateCreated.timeIntervalSince1970,
            playlist.dateModified.timeIntervalSince1970,
            playlist.isSmartPlaylist,
            playlist.smartCriteria as Any,
            playlist.trackCount
        ])
    }

    func getAll() -> [Playlist] {
        let sql = "SELECT * FROM playlists ORDER BY name"
        let results = db.query(sql: sql)
        return results.compactMap { rowToPlaylist($0) }
    }

    func getById(id: Int64) -> Playlist? {
        let sql = "SELECT * FROM playlists WHERE id = ?"
        let results = db.query(sql: sql, parameters: [id])
        return results.first.flatMap { rowToPlaylist($0) }
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
        return results.compactMap { trackDAO.trackFromRow($0) }
    }

    func reorderTracks(playlistId: Int64, trackIds: [Int64]) {
        db.inTransaction { ctx in
            for (index, trackId) in trackIds.enumerated() {
                ctx.execute(
                    sql: "UPDATE playlist_tracks SET position = ? WHERE playlist_id = ? AND track_id = ?",
                    parameters: [index, playlistId, trackId]
                )
            }
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

    // MARK: - Smart Playlist Support

    func getTracksForSmartPlaylist(criteria: SmartPlaylistCriteria) -> [Track] {
        let (whereClause, parameters) = buildSmartPlaylistQuery(criteria: criteria)

        var sql = "SELECT * FROM tracks"
        if !whereClause.isEmpty {
            sql += " WHERE \(whereClause)"
        }
        sql += " ORDER BY \(criteria.orderBy.sql)"
        if let limit = criteria.limit {
            sql += " LIMIT \(limit)"
        }

        let results = db.query(sql: sql, parameters: parameters)
        let trackDAO = TrackDAO()
        return results.compactMap { trackDAO.trackFromRow($0) }
    }

    func getSmartPlaylistTrackCount(criteria: SmartPlaylistCriteria) -> Int {
        let (whereClause, parameters) = buildSmartPlaylistQuery(criteria: criteria)

        var sql = "SELECT COUNT(*) as count FROM tracks"
        if !whereClause.isEmpty {
            sql += " WHERE \(whereClause)"
        }

        let result = db.query(sql: sql, parameters: parameters).first
        return Int(result?["count"] as? Int64 ?? 0)
    }

    private func buildSmartPlaylistQuery(criteria: SmartPlaylistCriteria) -> (String, [Any]) {
        var clauses: [String] = []
        var parameters: [Any] = []

        for rule in criteria.rules {
            if let (clause, params) = buildRuleClause(rule: rule) {
                clauses.append(clause)
                parameters.append(contentsOf: params)
            }
        }

        guard !clauses.isEmpty else { return ("", []) }

        let joiner = criteria.matchAll ? " AND " : " OR "
        let whereClause = clauses.joined(separator: joiner)
        return (whereClause, parameters)
    }

    private func buildRuleClause(rule: SmartPlaylistRule) -> (String, [Any])? {
        let column = rule.field.rawValue
        let value = rule.value

        if rule.field.isBool {
            let boolVal = (value.lowercased() == "true" || value == "1") ? 1 : 0
            return ("\(column) = ?", [boolVal])
        }

        if rule.field.isText {
            switch rule.comparison {
            case .contains:
                return ("\(column) LIKE ? ESCAPE '\\'", ["%\(escapeLike(value))%"])
            case .doesNotContain:
                return ("(\(column) NOT LIKE ? ESCAPE '\\' OR \(column) IS NULL)", ["%\(escapeLike(value))%"])
            case .equals:
                return ("\(column) = ?", [value])
            case .notEquals:
                return ("(\(column) != ? OR \(column) IS NULL)", [value])
            case .beginsWith:
                return ("\(column) LIKE ? ESCAPE '\\'", ["\(escapeLike(value))%"])
            case .endsWith:
                return ("\(column) LIKE ? ESCAPE '\\'", ["%\(escapeLike(value))"])
            default:
                return nil
            }
        }

        if rule.field.isNumeric {
            guard let numVal = Double(value) else { return nil }
            switch rule.comparison {
            case .equals: return ("\(column) = ?", [numVal])
            case .notEquals: return ("\(column) != ?", [numVal])
            case .greaterThan: return ("\(column) > ?", [numVal])
            case .lessThan: return ("\(column) < ?", [numVal])
            case .greaterOrEqual: return ("\(column) >= ?", [numVal])
            case .lessOrEqual: return ("\(column) <= ?", [numVal])
            default: return nil
            }
        }

        if rule.field.isDate {
            // Value is number of days for inTheLast/notInTheLast
            guard let days = Double(value) else { return nil }
            let threshold = Date().addingTimeInterval(-days * 86400).timeIntervalSince1970

            switch rule.comparison {
            case .inTheLast:
                return ("\(column) >= ?", [threshold])
            case .notInTheLast:
                return ("(\(column) < ? OR \(column) IS NULL)", [threshold])
            case .greaterThan:
                return ("\(column) > ?", [threshold])
            case .lessThan:
                return ("\(column) < ?", [threshold])
            default:
                return nil
            }
        }

        return nil
    }

    private func escapeLike(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "%", with: "\\%")
             .replacingOccurrences(of: "_", with: "\\_")
    }

    private func rowToPlaylist(_ row: [String: Any]) -> Playlist? {
        guard let id = row["id"] as? Int64,
              let name = row["name"] as? String,
              let dateCreated = row["date_created"] as? Double,
              let dateModified = row["date_modified"] as? Double else {
            return nil
        }

        return Playlist(
            id: id,
            name: name,
            dateCreated: Date(timeIntervalSince1970: dateCreated),
            dateModified: Date(timeIntervalSince1970: dateModified),
            isSmartPlaylist: (row["is_smart_playlist"] as? Int64 ?? 0) == 1,
            smartCriteria: row["smart_criteria"] as? String,
            trackCount: Int(row["track_count"] as? Int64 ?? 0)
        )
    }
}
