import Foundation
import SQLite3

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
            print("Error opening database at \(dbPath)")
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

        let tables = [
            createArtistsTable,
            createGenresTable,
            createComposersTable,
            createAlbumsTable,
            createTracksTable,
            createPlaylistsTable,
            createPlaylistTracksTable,
            createLibraryPathsTable
        ]

        for sql in tables {
            execute(sql: sql)
        }
    }

    func execute(sql: String, parameters: [Any] = []) {
        dbQueue.sync {
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let error = String(cString: sqlite3_errmsg(db))
                print("Error preparing statement: \(error)")
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
                    sqlite3_bind_text(statement, bindIndex, (value as NSString).utf8String, -1, nil)
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
                print("Error executing statement: \(error)")
            }
        }
    }

    func query(sql: String, parameters: [Any] = []) -> [[String: Any]] {
        var results: [[String: Any]] = []

        dbQueue.sync {
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let error = String(cString: sqlite3_errmsg(db))
                print("Error preparing query: \(error)")
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
                    sqlite3_bind_text(statement, bindIndex, (value as NSString).utf8String, -1, nil)
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

    func lastInsertRowId() -> Int64 {
        return sqlite3_last_insert_rowid(db)
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
