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
            createScrobbleQueueTable
        ]

        for sql in tables {
            execute(sql: sql)
        }

        runMigrations()
    }

    private func runMigrations() {
        let checkColumn = "PRAGMA table_info(tracks)"
        let columns = query(sql: checkColumn)
        let columnNames = Set(columns.compactMap { $0["name"] as? String })

        if !columnNames.contains("lyrics") {
            execute(sql: "ALTER TABLE tracks ADD COLUMN lyrics TEXT")
        }
        if !columnNames.contains("replay_gain_track") {
            execute(sql: "ALTER TABLE tracks ADD COLUMN replay_gain_track REAL")
        }
        if !columnNames.contains("replay_gain_album") {
            execute(sql: "ALTER TABLE tracks ADD COLUMN replay_gain_album REAL")
        }
        if !columnNames.contains("channel_count") {
            execute(sql: "ALTER TABLE tracks ADD COLUMN channel_count INTEGER")
        }
        if !columnNames.contains("format_name") {
            execute(sql: "ALTER TABLE tracks ADD COLUMN format_name TEXT")
        }
        if !columnNames.contains("bit_depth") {
            execute(sql: "ALTER TABLE tracks ADD COLUMN bit_depth INTEGER")
        }
        if !columnNames.contains("start_time") {
            execute(sql: "ALTER TABLE tracks ADD COLUMN start_time REAL")
        }
        if !columnNames.contains("end_time") {
            execute(sql: "ALTER TABLE tracks ADD COLUMN end_time REAL")
        }
        if !columnNames.contains("last_scan_time") {
            execute(sql: "ALTER TABLE tracks ADD COLUMN last_scan_time REAL")
        }

        // FTS5 virtual table for fast search
        execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5(
                title, artist_name, album_title, genre_name,
                content='tracks', content_rowid='id'
            )
        """)

        // Triggers to keep FTS in sync
        execute(sql: """
            CREATE TRIGGER IF NOT EXISTS tracks_ai AFTER INSERT ON tracks BEGIN
                INSERT INTO tracks_fts(rowid, title, artist_name, album_title, genre_name)
                VALUES (new.id, new.title, new.artist_name, new.album_title, new.genre_name);
            END
        """)
        execute(sql: """
            CREATE TRIGGER IF NOT EXISTS tracks_ad AFTER DELETE ON tracks BEGIN
                INSERT INTO tracks_fts(tracks_fts, rowid, title, artist_name, album_title, genre_name)
                VALUES ('delete', old.id, old.title, old.artist_name, old.album_title, old.genre_name);
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

    func beginTransaction() {
        dbQueue.sync {
            sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        }
    }

    func commitTransaction() {
        dbQueue.sync {
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

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
        let trackCount = query(sql: "SELECT COUNT(*) as count FROM tracks").first?["count"] as? Int64 ?? 0
        let albumCount = query(sql: "SELECT COUNT(*) as count FROM albums").first?["count"] as? Int64 ?? 0
        let artistCount = query(sql: "SELECT COUNT(*) as count FROM artists").first?["count"] as? Int64 ?? 0
        let duration = query(sql: "SELECT SUM(duration) as total FROM tracks").first?["total"] as? Double ?? 0

        return (Int(trackCount), Int(albumCount), Int(artistCount), duration)
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
}
