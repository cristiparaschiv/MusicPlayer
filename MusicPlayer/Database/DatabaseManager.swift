import Foundation
import SQLite3

// SQLITE_TRANSIENT tells SQLite to make its own copy of the string data
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.orangemusicplayer.database", qos: .userInitiated)

    private init() {
        openDatabase()
        createTables()
    }

    private func openDatabase() {
        let fileManager = FileManager.default
        let dbPath = fileManager.applicationSupportDirectory()
            .appendingPathComponent(Constants.databaseName)
            .path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            #if DEBUG
            print("Error opening database at \(dbPath)")
            #endif
            return
        }

        // Enable foreign keys
        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
        // Enable WAL mode for better concurrency
        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
    }

    private func createTables() {
        let createArtistsTable = """
        CREATE TABLE IF NOT EXISTS artists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            name_sort TEXT NOT NULL,
            album_count INTEGER DEFAULT 0,
            track_count INTEGER DEFAULT 0,
            profile_image_path TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_artists_name_sort ON artists(name_sort);
        """

        let createAlbumsTable = """
        CREATE TABLE IF NOT EXISTS albums (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            title_sort TEXT NOT NULL,
            artist_id INTEGER,
            artist_name TEXT,
            year INTEGER,
            genre_id INTEGER,
            genre_name TEXT,
            track_count INTEGER DEFAULT 0,
            total_duration REAL DEFAULT 0,
            date_added REAL NOT NULL,
            artwork_path TEXT,
            FOREIGN KEY(artist_id) REFERENCES artists(id) ON DELETE SET NULL,
            FOREIGN KEY(genre_id) REFERENCES genres(id) ON DELETE SET NULL
        );
        CREATE INDEX IF NOT EXISTS idx_albums_title_sort ON albums(title_sort);
        CREATE INDEX IF NOT EXISTS idx_albums_artist_id ON albums(artist_id);
        CREATE INDEX IF NOT EXISTS idx_albums_year ON albums(year);
        CREATE INDEX IF NOT EXISTS idx_albums_date_added ON albums(date_added);
        """

        let createGenresTable = """
        CREATE TABLE IF NOT EXISTS genres (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            track_count INTEGER DEFAULT 0
        );
        """

        let createComposersTable = """
        CREATE TABLE IF NOT EXISTS composers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            track_count INTEGER DEFAULT 0
        );
        """

        let createTracksTable = """
        CREATE TABLE IF NOT EXISTS tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            title_sort TEXT NOT NULL,
            artist_id INTEGER,
            artist_name TEXT,
            album_id INTEGER,
            album_title TEXT,
            album_artist_name TEXT,
            track_number INTEGER,
            disc_number INTEGER,
            year INTEGER,
            genre_id INTEGER,
            genre_name TEXT,
            composer_id INTEGER,
            composer_name TEXT,
            duration REAL NOT NULL,
            bitrate INTEGER,
            sample_rate INTEGER,
            file_path TEXT NOT NULL UNIQUE,
            file_size INTEGER NOT NULL,
            date_added REAL NOT NULL,
            date_modified REAL NOT NULL,
            last_played REAL,
            play_count INTEGER DEFAULT 0,
            rating INTEGER,
            is_favorite INTEGER DEFAULT 0,
            has_artwork INTEGER DEFAULT 0,
            FOREIGN KEY(artist_id) REFERENCES artists(id) ON DELETE SET NULL,
            FOREIGN KEY(album_id) REFERENCES albums(id) ON DELETE SET NULL,
            FOREIGN KEY(genre_id) REFERENCES genres(id) ON DELETE SET NULL,
            FOREIGN KEY(composer_id) REFERENCES composers(id) ON DELETE SET NULL
        );
        CREATE INDEX IF NOT EXISTS idx_tracks_title_sort ON tracks(title_sort);
        CREATE INDEX IF NOT EXISTS idx_tracks_artist_id ON tracks(artist_id);
        CREATE INDEX IF NOT EXISTS idx_tracks_album_id ON tracks(album_id);
        CREATE INDEX IF NOT EXISTS idx_tracks_genre_id ON tracks(genre_id);
        CREATE INDEX IF NOT EXISTS idx_tracks_year ON tracks(year);
        CREATE INDEX IF NOT EXISTS idx_tracks_date_added ON tracks(date_added);
        CREATE INDEX IF NOT EXISTS idx_tracks_last_played ON tracks(last_played);
        CREATE INDEX IF NOT EXISTS idx_tracks_play_count ON tracks(play_count);
        CREATE INDEX IF NOT EXISTS idx_tracks_is_favorite ON tracks(is_favorite);
        CREATE INDEX IF NOT EXISTS idx_tracks_file_path ON tracks(file_path);
        """

        let createPlaylistsTable = """
        CREATE TABLE IF NOT EXISTS playlists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            date_created REAL NOT NULL,
            date_modified REAL NOT NULL,
            is_smart_playlist INTEGER DEFAULT 0,
            smart_criteria TEXT,
            track_count INTEGER DEFAULT 0
        );
        """

        let createPlaylistTracksTable = """
        CREATE TABLE IF NOT EXISTS playlist_tracks (
            playlist_id INTEGER NOT NULL,
            track_id INTEGER NOT NULL,
            position INTEGER NOT NULL,
            date_added REAL NOT NULL,
            PRIMARY KEY(playlist_id, track_id),
            FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
            FOREIGN KEY(track_id) REFERENCES tracks(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_playlist_tracks_playlist_id ON playlist_tracks(playlist_id);
        CREATE INDEX IF NOT EXISTS idx_playlist_tracks_position ON playlist_tracks(playlist_id, position);
        """

        let createLibraryPathsTable = """
        CREATE TABLE IF NOT EXISTS library_paths (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL UNIQUE,
            date_added REAL NOT NULL,
            last_scanned REAL
        );
        """

        let createPlayHistoryTable = """
        CREATE TABLE IF NOT EXISTS play_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id INTEGER NOT NULL,
            played_at REAL NOT NULL,
            completed INTEGER DEFAULT 0,
            FOREIGN KEY(track_id) REFERENCES tracks(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_play_history_track_id ON play_history(track_id);
        CREATE INDEX IF NOT EXISTS idx_play_history_played_at ON play_history(played_at DESC);
        CREATE INDEX IF NOT EXISTS idx_play_history_completed_played_at ON play_history(completed, played_at);
        """

        let createScrobbleQueueTable = """
        CREATE TABLE IF NOT EXISTS lastfm_scrobble_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_title TEXT NOT NULL,
            artist TEXT NOT NULL,
            album TEXT,
            timestamp REAL NOT NULL,
            created_at REAL NOT NULL
        );
        """

        let createExternalTracksTable = """
        CREATE TABLE IF NOT EXISTS external_tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            title_sort TEXT NOT NULL,
            artist_name TEXT,
            album_title TEXT,
            album_artist_name TEXT,
            track_number INTEGER,
            disc_number INTEGER,
            year INTEGER,
            genre_name TEXT,
            composer_name TEXT,
            duration REAL NOT NULL,
            bitrate INTEGER,
            sample_rate INTEGER,
            channel_count INTEGER,
            bit_depth INTEGER,
            format_name TEXT,
            file_path TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            date_added REAL NOT NULL,
            has_artwork INTEGER DEFAULT 0,
            lyrics TEXT,
            replay_gain_track REAL,
            replay_gain_album REAL
        );
        """

        let createExternalPlaylistTracksTable = """
        CREATE TABLE IF NOT EXISTS external_playlist_tracks (
            track_id INTEGER NOT NULL,
            position INTEGER NOT NULL,
            date_added REAL NOT NULL,
            FOREIGN KEY(track_id) REFERENCES external_tracks(id) ON DELETE CASCADE
        );
        """

        let tables = [
            createArtistsTable,
            createGenresTable,
            createComposersTable,
            createAlbumsTable,
            createTracksTable,
            createPlaylistsTable,
            createPlaylistTracksTable,
            createLibraryPathsTable,
            createPlayHistoryTable,
            createScrobbleQueueTable,
            createExternalTracksTable,
            createExternalPlaylistTracksTable
        ]

        for sql in tables {
            executeBatch(sql: sql)
        }

        runMigrations()
    }

    // MARK: - Schema Versioning

    /// Each migration runs once, in order. Add new migrations at the end.
    private static let migrations: [(String, (DatabaseManager) -> Void)] = [
        // Migration 1: Add extra track columns
        ("Add lyrics, replay_gain, channel_count, format_name, bit_depth, start/end_time, last_scan_time columns", { db in
            let columns = db._query(sql: "PRAGMA table_info(tracks)")
            let existing = Set(columns.compactMap { $0["name"] as? String })
            let additions: [(String, String)] = [
                ("lyrics", "TEXT"), ("replay_gain_track", "REAL"), ("replay_gain_album", "REAL"),
                ("channel_count", "INTEGER"), ("format_name", "TEXT"), ("bit_depth", "INTEGER"),
                ("start_time", "REAL"), ("end_time", "REAL"), ("last_scan_time", "REAL")
            ]
            for (col, type) in additions where !existing.contains(col) {
                db._execute(sql: "ALTER TABLE tracks ADD COLUMN \(col) \(type)")
            }
        }),
        // Migration 2: FTS5 full-text search
        ("Create FTS5 virtual table and sync triggers", { db in
            db._execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5(
                    title, artist_name, album_title, genre_name,
                    content='tracks', content_rowid='id'
                )
            """)
            db._execute(sql: """
                CREATE TRIGGER IF NOT EXISTS tracks_ai AFTER INSERT ON tracks BEGIN
                    INSERT INTO tracks_fts(rowid, title, artist_name, album_title, genre_name)
                    VALUES (new.id, new.title, new.artist_name, new.album_title, new.genre_name);
                END
            """)
            db._execute(sql: """
                CREATE TRIGGER IF NOT EXISTS tracks_ad AFTER DELETE ON tracks BEGIN
                    INSERT INTO tracks_fts(tracks_fts, rowid, title, artist_name, album_title, genre_name)
                    VALUES ('delete', old.id, old.title, old.artist_name, old.album_title, old.genre_name);
                END
            """)
            db._execute(sql: """
                CREATE TRIGGER IF NOT EXISTS tracks_au AFTER UPDATE ON tracks BEGIN
                    INSERT INTO tracks_fts(tracks_fts, rowid, title, artist_name, album_title, genre_name)
                    VALUES ('delete', old.id, old.title, old.artist_name, old.album_title, old.genre_name);
                    INSERT INTO tracks_fts(rowid, title, artist_name, album_title, genre_name)
                    VALUES (new.id, new.title, new.artist_name, new.album_title, new.genre_name);
                END
            """)
        }),
        // Migration 3: Add missing indexes
        ("Add missing indexes on tracks.composer_id and playlist_tracks.track_id", { db in
            db._execute(sql: "CREATE INDEX IF NOT EXISTS idx_tracks_composer_id ON tracks(composer_id)")
            db._execute(sql: "CREATE INDEX IF NOT EXISTS idx_playlist_tracks_track_id ON playlist_tracks(track_id)")
        }),
    ]

    private func runMigrations() {
        // Ensure schema_version table exists
        dbQueue.sync {
            _execute(sql: "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL DEFAULT 0)")
            let rows = _query(sql: "SELECT version FROM schema_version")
            if rows.isEmpty {
                // Bootstrap: detect if this is an existing database by checking for tracks table columns
                let columns = _query(sql: "PRAGMA table_info(tracks)")
                let existing = Set(columns.compactMap { $0["name"] as? String })
                let startVersion = existing.contains("lyrics") ? Int64(Self.migrations.count) : 0
                _execute(sql: "INSERT INTO schema_version (version) VALUES (?)", parameters: [startVersion])
            }
        }

        let currentVersion: Int64 = dbQueue.sync {
            _query(sql: "SELECT version FROM schema_version").first?["version"] as? Int64 ?? 0
        }

        for i in Int(currentVersion)..<Self.migrations.count {
            let (name, migration) = Self.migrations[i]
            dbQueue.sync {
                _execute(sql: "BEGIN")
                migration(self)
                _execute(sql: "UPDATE schema_version SET version = ?", parameters: [Int64(i + 1)])
                _execute(sql: "COMMIT")
            }
            #if DEBUG
            print("[DatabaseManager] Ran migration \(i + 1): \(name)")
            #endif
        }
    }

    func rebuildFTSIndex() {
        execute(sql: "INSERT OR IGNORE INTO tracks_fts(tracks_fts) VALUES('rebuild')")
    }

    func disableFTSTriggers() {
        execute(sql: "DROP TRIGGER IF EXISTS tracks_ai")
        execute(sql: "DROP TRIGGER IF EXISTS tracks_au")
    }

    func enableFTSTriggers() {
        execute(sql: """
            CREATE TRIGGER IF NOT EXISTS tracks_ai AFTER INSERT ON tracks BEGIN
                INSERT INTO tracks_fts(rowid, title, artist_name, album_title, genre_name)
                VALUES (new.id, new.title, new.artist_name, new.album_title, new.genre_name);
            END
        """)
        execute(sql: """
            CREATE TRIGGER IF NOT EXISTS tracks_au AFTER UPDATE ON tracks BEGIN
                INSERT INTO tracks_fts(tracks_fts, rowid, title, artist_name, album_title, genre_name)
                VALUES ('delete', old.id, old.title, old.artist_name, old.album_title, old.genre_name);
                INSERT INTO tracks_fts(rowid, title, artist_name, album_title, genre_name)
                VALUES (new.id, new.title, new.artist_name, new.album_title, new.genre_name);
            END
        """)
    }

    /// Execute multiple SQL statements (DDL only — no parameter binding).
    /// Uses sqlite3_exec which handles multi-statement strings.
    func executeBatch(sql: String) {
        dbQueue.sync {
            var errorMessage: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
                let error = errorMessage.map { String(cString: $0) } ?? "Unknown error"
                sqlite3_free(errorMessage)
                #if DEBUG
                print("[DatabaseManager] Error executing batch SQL: \(error)")
                #endif
            }
        }
    }

    func execute(sql: String, parameters: [Any] = []) {
        dbQueue.sync {
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let error = String(cString: sqlite3_errmsg(db))
                #if DEBUG
                print("Error preparing statement: \(error)")
                #endif
                return
            }

            defer {
                sqlite3_finalize(statement)
            }

            // Bind parameters
            for (index, param) in parameters.enumerated() {
                let bindIndex = Int32(index + 1)

                switch param {
                case let value as String:
                    sqlite3_bind_text(statement, bindIndex, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
                case let value as Int:
                    sqlite3_bind_int64(statement, bindIndex, Int64(value))
                case let value as Int64:
                    sqlite3_bind_int64(statement, bindIndex, value)
                case let value as Double:
                    sqlite3_bind_double(statement, bindIndex, value)
                case let value as Bool:
                    sqlite3_bind_int(statement, bindIndex, value ? 1 : 0)
                case is NSNull:
                    sqlite3_bind_null(statement, bindIndex)
                default:
                    sqlite3_bind_null(statement, bindIndex)
                }
            }

            if sqlite3_step(statement) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                #if DEBUG
                print("Error executing statement: \(error)")
                #endif
            }
        }
    }

    func query(sql: String, parameters: [Any] = []) -> [[String: Any]] {
        var results: [[String: Any]] = []

        dbQueue.sync {
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let error = String(cString: sqlite3_errmsg(db))
                #if DEBUG
                print("[DatabaseManager] Error preparing query: \(error)")
                print("[DatabaseManager] SQL: \(sql)")
                #endif
                return
            }

            defer {
                sqlite3_finalize(statement)
            }

            // Bind parameters
            for (index, param) in parameters.enumerated() {
                let bindIndex = Int32(index + 1)

                switch param {
                case let value as String:
                    sqlite3_bind_text(statement, bindIndex, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
                case let value as Int:
                    sqlite3_bind_int64(statement, bindIndex, Int64(value))
                case let value as Int64:
                    sqlite3_bind_int64(statement, bindIndex, value)
                case let value as Double:
                    sqlite3_bind_double(statement, bindIndex, value)
                case let value as Bool:
                    sqlite3_bind_int(statement, bindIndex, value ? 1 : 0)
                case is NSNull:
                    sqlite3_bind_null(statement, bindIndex)
                default:
                    sqlite3_bind_null(statement, bindIndex)
                }
            }

            // Fetch results
            while sqlite3_step(statement) == SQLITE_ROW {
                var row: [String: Any] = [:]
                let columnCount = sqlite3_column_count(statement)

                for i in 0..<columnCount {
                    let columnName = String(cString: sqlite3_column_name(statement, i))
                    let columnType = sqlite3_column_type(statement, i)

                    switch columnType {
                    case SQLITE_INTEGER:
                        row[columnName] = sqlite3_column_int64(statement, i)
                    case SQLITE_FLOAT:
                        row[columnName] = sqlite3_column_double(statement, i)
                    case SQLITE_TEXT:
                        if let text = sqlite3_column_text(statement, i) {
                            row[columnName] = String(cString: text)
                        }
                    case SQLITE_NULL:
                        row[columnName] = NSNull()
                    default:
                        break
                    }
                }

                results.append(row)
            }
        }

        return results
    }

    /// Execute an INSERT and return the last insert row ID atomically
    @discardableResult
    func executeInsert(sql: String, parameters: [Any] = []) -> Int64 {
        var rowId: Int64 = 0
        dbQueue.sync {
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let error = String(cString: sqlite3_errmsg(db))
                #if DEBUG
                print("Error preparing statement: \(error)")
                #endif
                return
            }

            defer {
                sqlite3_finalize(statement)
            }

            for (index, param) in parameters.enumerated() {
                let bindIndex = Int32(index + 1)

                switch param {
                case let value as String:
                    sqlite3_bind_text(statement, bindIndex, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
                case let value as Int:
                    sqlite3_bind_int64(statement, bindIndex, Int64(value))
                case let value as Int64:
                    sqlite3_bind_int64(statement, bindIndex, value)
                case let value as Double:
                    sqlite3_bind_double(statement, bindIndex, value)
                case let value as Bool:
                    sqlite3_bind_int(statement, bindIndex, value ? 1 : 0)
                case is NSNull:
                    sqlite3_bind_null(statement, bindIndex)
                default:
                    sqlite3_bind_null(statement, bindIndex)
                }
            }

            if sqlite3_step(statement) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                #if DEBUG
                print("Error executing statement: \(error)")
                #endif
            }

            rowId = sqlite3_last_insert_rowid(db)
        }
        return rowId
    }

    // MARK: - Internal methods (no dispatch — call only from within dbQueue.sync)

    /// Internal execute — no queue dispatch. Must be called within dbQueue.sync.
    private func _execute(sql: String, parameters: [Any] = []) {
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            #if DEBUG
            print("[DatabaseManager] Error preparing statement: \(error)")
            #endif
            return
        }

        defer { sqlite3_finalize(statement) }
        _bindParameters(statement: statement, parameters: parameters)

        if sqlite3_step(statement) != SQLITE_DONE {
            let error = String(cString: sqlite3_errmsg(db))
            #if DEBUG
            print("[DatabaseManager] Error executing statement: \(error)")
            #endif
        }
    }

    /// Internal query — no queue dispatch. Must be called within dbQueue.sync.
    private func _query(sql: String, parameters: [Any] = []) -> [[String: Any]] {
        var results: [[String: Any]] = []
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            #if DEBUG
            print("[DatabaseManager] Error preparing query: \(error)")
            #endif
            return results
        }

        defer { sqlite3_finalize(statement) }
        _bindParameters(statement: statement, parameters: parameters)

        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]
            let columnCount = sqlite3_column_count(statement)

            for i in 0..<columnCount {
                let columnName = String(cString: sqlite3_column_name(statement, i))
                let columnType = sqlite3_column_type(statement, i)

                switch columnType {
                case SQLITE_INTEGER:
                    row[columnName] = sqlite3_column_int64(statement, i)
                case SQLITE_FLOAT:
                    row[columnName] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, i) {
                        row[columnName] = String(cString: text)
                    }
                case SQLITE_NULL:
                    row[columnName] = NSNull()
                default:
                    break
                }
            }

            results.append(row)
        }

        return results
    }

    /// Internal executeInsert — no queue dispatch. Must be called within dbQueue.sync.
    @discardableResult
    private func _executeInsert(sql: String, parameters: [Any] = []) -> Int64 {
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            #if DEBUG
            print("[DatabaseManager] Error preparing statement: \(error)")
            #endif
            return 0
        }

        defer { sqlite3_finalize(statement) }
        _bindParameters(statement: statement, parameters: parameters)

        if sqlite3_step(statement) != SQLITE_DONE {
            let error = String(cString: sqlite3_errmsg(db))
            #if DEBUG
            print("[DatabaseManager] Error executing statement: \(error)")
            #endif
        }

        return sqlite3_last_insert_rowid(db)
    }

    private func _bindParameters(statement: OpaquePointer?, parameters: [Any]) {
        for (index, param) in parameters.enumerated() {
            let bindIndex = Int32(index + 1)

            switch param {
            case let value as String:
                sqlite3_bind_text(statement, bindIndex, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
            case let value as Int:
                sqlite3_bind_int64(statement, bindIndex, Int64(value))
            case let value as Int64:
                sqlite3_bind_int64(statement, bindIndex, value)
            case let value as Double:
                sqlite3_bind_double(statement, bindIndex, value)
            case let value as Bool:
                sqlite3_bind_int(statement, bindIndex, value ? 1 : 0)
            case is NSNull:
                sqlite3_bind_null(statement, bindIndex)
            default:
                sqlite3_bind_null(statement, bindIndex)
            }
        }
    }

    // MARK: - Throwing API (Phase 1)

    enum DatabaseError: Error, LocalizedError {
        case prepareFailed(String)
        case executionFailed(String)

        var errorDescription: String? {
            switch self {
            case .prepareFailed(let msg): return "SQL prepare failed: \(msg)"
            case .executionFailed(let msg): return "SQL execution failed: \(msg)"
            }
        }
    }

    func tryExecute(sql: String, parameters: [Any] = []) throws {
        try dbQueue.sync {
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }

            defer { sqlite3_finalize(statement) }
            _bindParameters(statement: statement, parameters: parameters)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    func tryQuery(sql: String, parameters: [Any] = []) throws -> [[String: Any]] {
        try dbQueue.sync {
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }

            defer { sqlite3_finalize(statement) }
            _bindParameters(statement: statement, parameters: parameters)

            var results: [[String: Any]] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                var row: [String: Any] = [:]
                let columnCount = sqlite3_column_count(statement)
                for i in 0..<columnCount {
                    let columnName = String(cString: sqlite3_column_name(statement, i))
                    let columnType = sqlite3_column_type(statement, i)
                    switch columnType {
                    case SQLITE_INTEGER: row[columnName] = sqlite3_column_int64(statement, i)
                    case SQLITE_FLOAT: row[columnName] = sqlite3_column_double(statement, i)
                    case SQLITE_TEXT:
                        if let text = sqlite3_column_text(statement, i) { row[columnName] = String(cString: text) }
                    case SQLITE_NULL: row[columnName] = NSNull()
                    default: break
                    }
                }
                results.append(row)
            }
            return results
        }
    }

    // MARK: - Transaction API

    /// Execute a block within a database transaction. Automatically rolls back on error.
    /// The block runs entirely within dbQueue.sync — do NOT call public execute/query/executeInsert
    /// from inside the block. Use the provided TransactionContext instead.
    func inTransaction(_ block: (TransactionContext) throws -> Void) rethrows {
        try dbQueue.sync {
            _execute(sql: "BEGIN")
            do {
                let ctx = TransactionContext(manager: self)
                try block(ctx)
                _execute(sql: "COMMIT")
            } catch {
                _execute(sql: "ROLLBACK")
                throw error
            }
        }
    }

    /// Context object passed to inTransaction blocks, providing safe database access.
    class TransactionContext {
        private let manager: DatabaseManager

        fileprivate init(manager: DatabaseManager) {
            self.manager = manager
        }

        func execute(sql: String, parameters: [Any] = []) {
            manager._execute(sql: sql, parameters: parameters)
        }

        func query(sql: String, parameters: [Any] = []) -> [[String: Any]] {
            manager._query(sql: sql, parameters: parameters)
        }

        @discardableResult
        func executeInsert(sql: String, parameters: [Any] = []) -> Int64 {
            manager._executeInsert(sql: sql, parameters: parameters)
        }
    }

    @available(*, deprecated, message: "Use inTransaction(_:) instead")
    func beginTransaction() {
        dbQueue.sync {
            sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        }
    }

    @available(*, deprecated, message: "Use inTransaction(_:) instead")
    func commitTransaction() {
        dbQueue.sync {
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    @available(*, deprecated, message: "Use inTransaction(_:) instead")
    func rollbackTransaction() {
        dbQueue.sync {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
        }
    }

    func lastInsertRowId() -> Int64 {
        return dbQueue.sync {
            sqlite3_last_insert_rowid(db)
        }
    }

    func getLibraryStats() -> (tracks: Int, albums: Int, artists: Int, totalDuration: TimeInterval) {
        // Wrap in a single dbQueue.sync for consistent snapshot
        return dbQueue.sync {
            let trackCount = _query(sql: "SELECT COUNT(*) as count FROM tracks").first?["count"] as? Int64 ?? 0
            let albumCount = _query(sql: "SELECT COUNT(*) as count FROM albums").first?["count"] as? Int64 ?? 0
            let artistCount = _query(sql: "SELECT COUNT(*) as count FROM artists").first?["count"] as? Int64 ?? 0
            let duration = _query(sql: "SELECT SUM(duration) as total FROM tracks").first?["total"] as? Double ?? 0

            return (Int(trackCount), Int(albumCount), Int(artistCount), duration)
        }
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
}
