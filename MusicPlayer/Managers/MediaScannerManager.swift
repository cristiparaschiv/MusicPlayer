import Foundation
import SFBAudioEngine

class MediaScannerManager {
    static let shared = MediaScannerManager()

    private let trackDAO = TrackDAO()
    private let albumDAO = AlbumDAO()
    private let artistDAO = ArtistDAO()

    private let scanQueue = DispatchQueue(label: "com.orangemusicplayer.scanner", qos: .userInitiated)
    private let fileSystemMonitor = FileSystemMonitor()

    private var isCurrentlyScanning = false
    private let scanLock = NSLock()

    private let artworkManager = ArtworkManager.shared
    
    // Supported audio file extensions
    private let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "alac", "wav", "aiff", "aif",
        "ogg", "opus", "wma", "ape", "dsf", "dff"
    ]

    private init() {
        setupFileSystemMonitoring()
    }
    
    func isLibraryEmpty() -> Bool {
        let db = DatabaseManager.shared
        let sql = "SELECT COUNT(*) FROM library_paths"
        let results = db.query(sql: sql)
        
        return (results.first?["COUNT(*)"] as? Int64) ?? 0 == 0
    }
    
    func addLibraryPath(_ path: String, triggerScan: Bool = true) {
        let db = DatabaseManager.shared
        let sql = "INSERT OR IGNORE INTO library_paths (path, date_added) VALUES (?, ?)"
        db.execute(sql: sql, parameters: [path, Date().timeIntervalSince1970])

        // Restart file system monitoring with updated paths
        startMonitoring()

        // Post notification that library paths changed
        NotificationCenter.default.post(name: Constants.Notifications.libraryPathsChanged, object: nil)

        // Automatically scan for music files if requested
        if triggerScan {
            scanForChanges()
        }
    }
    
    func getLibraryPaths() -> [String] {
        let db = DatabaseManager.shared
        let sql = "SELECT path FROM library_paths ORDER BY date_added DESC"
        let results = db.query(sql: sql)

        return results.compactMap { $0["path"] as? String }
    }

    func removeLibraryPath(_ path: String) {
        let db = DatabaseManager.shared
        let sql = "DELETE FROM library_paths WHERE path = ?"
        db.execute(sql: sql, parameters: [path])

        // Remove security-scoped bookmark
        SecurityBookmarkManager.shared.removeBookmark(for: path)

        // Optionally, remove tracks associated with this path
        let deleteTracksSql = "DELETE FROM tracks WHERE file_path LIKE ?"
        db.execute(sql: deleteTracksSql, parameters: [path + "%"])

        // Restart file system monitoring with updated paths
        startMonitoring()

        // Post notifications that library was updated
        NotificationCenter.default.post(name: Constants.Notifications.libraryPathsChanged, object: nil)
        NotificationCenter.default.post(name: Constants.Notifications.libraryDidUpdate, object: nil)
    }

    func fullRescan() {
        // Delete all existing tracks, albums, and artists
        let db = DatabaseManager.shared

        db.execute(sql: "DELETE FROM playlist_tracks")
        db.execute(sql: "DELETE FROM tracks")
        db.execute(sql: "DELETE FROM albums")
        db.execute(sql: "DELETE FROM artists")
        db.execute(sql: "DELETE FROM genres")
        db.execute(sql: "DELETE FROM composers")

        // Reset last_scanned for all library paths
        db.execute(sql: "UPDATE library_paths SET last_scanned = NULL")

        // Trigger scan for all paths
        scanForChanges()
    }

    func scanForChanges() {
        scanQueue.async { [weak self] in
            self?.performScan(fullRescan: false)
        }
    }

    // MARK: - File System Monitoring

    private func setupFileSystemMonitoring() {
        fileSystemMonitor.onPathsChanged = { [weak self] in
            self?.scanForChanges()
        }
    }

    func startMonitoring() {
        let paths = getLibraryPaths()
        fileSystemMonitor.startMonitoring(paths: paths)
    }

    func stopMonitoring() {
        fileSystemMonitor.stopMonitoring()
    }

    // MARK: - Scanning Implementation

    private func performScan(fullRescan: Bool) {
        scanLock.lock()
        guard !isCurrentlyScanning else {
            scanLock.unlock()
            print("Scan already in progress, skipping...")
            return
        }
        isCurrentlyScanning = true
        scanLock.unlock()

        defer {
            scanLock.lock()
            isCurrentlyScanning = false
            scanLock.unlock()
        }

        let paths = getLibraryPaths()
        print("Scanning \(paths.count) library paths...")

        let db = DatabaseManager.shared
        var allProcessedFiles = Set<String>()

        for libraryPath in paths {
            let url = URL(fileURLWithPath: libraryPath)

            guard FileManager.default.fileExists(atPath: libraryPath) else {
                print("Library path does not exist: \(libraryPath)")
                continue
            }

            let audioFiles = findAudioFiles(in: url)
            print("Found \(audioFiles.count) audio files in \(libraryPath)")

            for (index, fileURL) in audioFiles.enumerated() {
                if index % 100 == 0 {
                    print("Processing file \(index + 1) of \(audioFiles.count)...")
                }

                let filePath = fileURL.path
                allProcessedFiles.insert(filePath)

                // Check if file exists in database
                let existingTrack = trackDAO.getTrack(byPath: filePath)

                // Get file modification date
                let fileAttributes = try? FileManager.default.attributesOfItem(atPath: filePath)
                let modificationDate = fileAttributes?[.modificationDate] as? Date ?? Date()

                // Skip if file hasn't been modified and we're not doing a full rescan
                if !fullRescan, let existing = existingTrack {
                    if existing.dateModified >= modificationDate {
                        continue
                    }
                }

                // Extract metadata and update/insert track
                if let metadata = extractMetadata(from: fileURL) {
                    if existingTrack != nil {
                        trackDAO.updateTrack(metadata: metadata, filePath: filePath)
                    } else {
                        trackDAO.insertTrack(metadata: metadata)
                    }
                }
                
            }

            // Update last_scanned timestamp
            let now = Date().timeIntervalSince1970
            db.execute(sql: "UPDATE library_paths SET last_scanned = ? WHERE path = ?",
                      parameters: [now, libraryPath])
        }

        // Remove tracks that no longer exist
        if !fullRescan {
            removeDeletedTracks(existingFiles: allProcessedFiles, libraryPaths: paths)
        }

        // Update album and artist counts
        updateLibraryStatistics()

        // Post notification that library was updated
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Constants.Notifications.libraryDidUpdate, object: nil)
        }

        print("Scan completed!")
    }

    private func findAudioFiles(in directory: URL) -> [URL] {
        var audioFiles: [URL] = []
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return audioFiles
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  let isRegularFile = resourceValues.isRegularFile,
                  isRegularFile else {
                continue
            }

            let fileExtension = fileURL.pathExtension.lowercased()
            if supportedExtensions.contains(fileExtension) {
                audioFiles.append(fileURL)
            }
        }

        return audioFiles
    }

    private func extractMetadata(from url: URL) -> AudioMetadata? {
        // Get file attributes first
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = fileAttributes[.size] as? Int64,
              let modificationDate = fileAttributes[.modificationDate] as? Date else {
            return nil
        }

        // Try to open the audio file with SFBAudioEngine
        guard let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: url) else {
            print("Failed to read audio file: \(url.path)")
            return nil
        }

        // Get audio properties
        let properties = audioFile.properties
        guard let duration = properties.duration, duration > 0 else {
            print("Invalid audio properties for: \(url.path)")
            return nil
        }

        // Initialize metadata struct
        var metadata = AudioMetadata(
            filePath: url.path,
            fileSize: fileSize,
            duration: duration,
            dateModified: modificationDate
        )

        // Extract metadata
        let audioMetadata = audioFile.metadata

        // Basic metadata
        metadata.title = audioMetadata.title
        metadata.artist = audioMetadata.artist
        metadata.album = audioMetadata.albumTitle
        metadata.albumArtist = audioMetadata.albumArtist
        metadata.genre = audioMetadata.genre
        metadata.composer = audioMetadata.composer

        // Track and disc numbers
        if let trackNum = audioMetadata.trackNumber {
            metadata.trackNumber = trackNum
        }
        if let discNum = audioMetadata.discNumber {
            metadata.discNumber = discNum
        }

        // Release date / year
        if let releaseDate = audioMetadata.releaseDate {
            metadata.year = extractYear(from: releaseDate)
        }

        // Additional metadata
        metadata.grouping = audioMetadata.grouping
        metadata.comment = audioMetadata.comment

        // Lyrics
        metadata.lyrics = audioMetadata.lyrics

        // Ratings
        if let rating = audioMetadata.rating {
            metadata.rating = rating
        }

        // ReplayGain information
        if let replayGainTrackGain = audioMetadata.replayGainTrackGain {
            metadata.replayGainTrackGain = replayGainTrackGain
        }
        if let replayGainAlbumGain = audioMetadata.replayGainAlbumGain {
            metadata.replayGainAlbumGain = replayGainAlbumGain
        }

        // BPM
        if let bpm = audioMetadata.bpm {
            metadata.bpm = bpm
        }

        // Get technical audio properties
        if let sampleRate = properties.sampleRate {
            metadata.sampleRate = Int(sampleRate)
        }
        if let bitrate = properties.bitrate {
            metadata.bitrate = Int(bitrate / 1000) // Convert to kbps
        }
        if let channelCount = properties.channelCount {
            metadata.channelCount = Int(channelCount)
        }

        // Format info
        metadata.formatName = properties.formatName

        // Use filename as title if no title metadata
        if metadata.title == nil || metadata.title?.isEmpty == true {
            metadata.title = url.deletingPathExtension().lastPathComponent
        }

        return metadata
    }

    private func extractYear(from dateString: String) -> Int? {
        // Try different date formats
        let dateFormatters = [
            "yyyy-MM-dd",
            "yyyy-MM",
            "yyyy"
        ]

        for format in dateFormatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                let calendar = Calendar.current
                return calendar.component(.year, from: date)
            }
        }

        // Try to extract just the year if it's a 4-digit number
        if dateString.count >= 4 {
            let yearString = String(dateString.prefix(4))
            return Int(yearString)
        }

        return nil
    }

    private func removeDeletedTracks(existingFiles: Set<String>, libraryPaths: [String]) {
        let db = DatabaseManager.shared

        for libraryPath in libraryPaths {
            let sql = "SELECT id, file_path FROM tracks WHERE file_path LIKE ?"
            let results = db.query(sql: sql, parameters: [libraryPath + "%"])

            for row in results {
                if let filePath = row["file_path"] as? String,
                   !existingFiles.contains(filePath),
                   !FileManager.default.fileExists(atPath: filePath) {
                    if let trackId = row["id"] as? Int64 {
                        trackDAO.deleteTrack(id: trackId)
                    }
                }
            }
        }
    }

    private func updateLibraryStatistics() {
        let db = DatabaseManager.shared

        // Update artist statistics
        db.execute(sql: """
            UPDATE artists SET
                album_count = (SELECT COUNT(DISTINCT album_id) FROM tracks WHERE artist_id = artists.id),
                track_count = (SELECT COUNT(*) FROM tracks WHERE artist_id = artists.id)
        """)

        // Update album statistics
        db.execute(sql: """
            UPDATE albums SET
                track_count = (SELECT COUNT(*) FROM tracks WHERE album_id = albums.id),
                total_duration = (SELECT COALESCE(SUM(duration), 0) FROM tracks WHERE album_id = albums.id)
        """)

        // Update genre statistics
        db.execute(sql: """
            UPDATE genres SET
                track_count = (SELECT COUNT(*) FROM tracks WHERE genre_id = genres.id)
        """)

        // Update composer statistics
        db.execute(sql: """
            UPDATE composers SET
                track_count = (SELECT COUNT(*) FROM tracks WHERE composer_id = composers.id)
        """)

        // Clean up unused entries
        db.execute(sql: "DELETE FROM artists WHERE track_count = 0")
        db.execute(sql: "DELETE FROM albums WHERE track_count = 0")
        db.execute(sql: "DELETE FROM genres WHERE track_count = 0")
        db.execute(sql: "DELETE FROM composers WHERE track_count = 0")
    }

    // MARK: - Search and Filtering

    func searchTracks(query: String) -> [Track] {
        guard !query.isEmpty else {
            return []
        }

        let searchPattern = "%\(query)%"
        let sql = """
            SELECT * FROM tracks
            WHERE title LIKE ? OR artist_name LIKE ? OR album_title LIKE ? OR album_artist_name LIKE ?
            ORDER BY title_sort
            LIMIT 100
        """

        let results = DatabaseManager.shared.query(
            sql: sql,
            parameters: [searchPattern, searchPattern, searchPattern, searchPattern]
        )

        return results.compactMap { trackDAO.trackFromRow($0) }
    }

    func filterTracks(
        artist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        year: Int? = nil,
        isFavorite: Bool? = nil,
        sortBy: TrackSortOption = .title,
        ascending: Bool = true
    ) -> [Track] {
        var sql = "SELECT * FROM tracks WHERE 1=1"
        var parameters: [Any] = []

        if let artist = artist {
            sql += " AND (artist_name = ? OR album_artist_name = ?)"
            parameters.append(artist)
            parameters.append(artist)
        }

        if let album = album {
            sql += " AND album_title = ?"
            parameters.append(album)
        }

        if let genre = genre {
            sql += " AND genre_name = ?"
            parameters.append(genre)
        }

        if let year = year {
            sql += " AND year = ?"
            parameters.append(year)
        }

        if let isFavorite = isFavorite {
            sql += " AND is_favorite = ?"
            parameters.append(isFavorite ? 1 : 0)
        }

        // Add sorting
        let sortColumn: String
        switch sortBy {
        case .title:
            sortColumn = "title_sort"
        case .artist:
            sortColumn = "artist_name"
        case .album:
            sortColumn = "album_title"
        case .year:
            sortColumn = "year"
        case .dateAdded:
            sortColumn = "date_added"
        case .playCount:
            sortColumn = "play_count"
        case .duration:
            sortColumn = "duration"
        }

        sql += " ORDER BY \(sortColumn) \(ascending ? "ASC" : "DESC")"

        let results = DatabaseManager.shared.query(sql: sql, parameters: parameters)
        return results.compactMap { trackDAO.trackFromRow($0) }
    }
}

// MARK: - Supporting Types

struct AudioMetadata {
    // File properties
    let filePath: String
    let fileSize: Int64
    let duration: TimeInterval
    let dateModified: Date

    // Basic metadata
    var title: String?
    var artist: String?
    var albumArtist: String?
    var album: String?
    var genre: String?
    var composer: String?
    var year: Int?
    var trackNumber: Int?
    var discNumber: Int?

    // Additional metadata
    var grouping: String?
    var comment: String?
    var lyrics: String?
    var rating: Int?
    var bpm: Int?

    // Technical properties
    var bitrate: Int?
    var sampleRate: Int?
    var channelCount: Int?
    var formatName: String?

    // ReplayGain
    var replayGainTrackGain: Double?
    var replayGainAlbumGain: Double?
}

enum TrackSortOption {
    case title
    case artist
    case album
    case year
    case dateAdded
    case playCount
    case duration
}
