import Combine
import Foundation
import SFBAudioEngine

struct LibraryPathStatus: Identifiable {
    let id: String
    let path: String
    let isAvailable: Bool
    let isNetworkVolume: Bool
    let scanState: ScanState

    enum ScanState {
        case idle
        case scanning(processed: Int, total: Int)
        case complete(trackCount: Int)
        case unavailable
    }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

class MediaScannerManager: ObservableObject {
    static let shared = MediaScannerManager()

    private let trackDAO = TrackDAO()
    private let albumDAO = AlbumDAO()
    private let artistDAO = ArtistDAO()

    private let scanQueue = DispatchQueue(label: "com.orangemusicplayer.scanner", qos: .userInitiated)
    private let fileSystemMonitor = FileSystemMonitor()

    private var isCurrentlyScanning = false
    private let scanLock = NSLock()

    private let artworkManager = ArtworkManager.shared

    @Published var isScanningPublished = false
    @Published var scanProgress: String = ""
    @Published var pathStatuses: [LibraryPathStatus] = []
    
    // Supported audio file extensions
    private let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "alac", "wav", "aiff", "aif",
        "ogg", "opus", "wma", "ape", "dsf", "dff", "wv", "mpc", "caf"
    ]

    private init() {
        setupFileSystemMonitoring()
        refreshPathStatuses()
    }

    /// Check if a path is on a network volume (SMB, AFP, NFS, etc.)
    static func isNetworkVolume(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let resourceValues = try? url.resourceValues(forKeys: [.volumeIsLocalKey]) else {
            return false
        }
        return resourceValues.volumeIsLocal == false
    }

    /// Refresh the availability status of all library paths
    func refreshPathStatuses() {
        let paths = getLibraryPaths()
        let statuses = paths.map { path -> LibraryPathStatus in
            let available = FileManager.default.fileExists(atPath: path)
            let isNetwork = Self.isNetworkVolume(path: path)
            let state: LibraryPathStatus.ScanState = available ? .idle : .unavailable
            return LibraryPathStatus(id: path, path: path, isAvailable: available, isNetworkVolume: isNetwork, scanState: state)
        }
        DispatchQueue.main.async {
            self.pathStatuses = statuses
        }
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

        // Remove tracks associated with this path
        let escapedPath = path.replacingOccurrences(of: "%", with: "\\%")
                              .replacingOccurrences(of: "_", with: "\\_")
        let deleteTracksSql = "DELETE FROM tracks WHERE file_path LIKE ? ESCAPE '\\'"
        db.execute(sql: deleteTracksSql, parameters: [escapedPath + "/%"])

        // Restart file system monitoring with updated paths
        startMonitoring()

        // Post notifications that library was updated
        NotificationCenter.default.post(name: Constants.Notifications.libraryPathsChanged, object: nil)
        NotificationCenter.default.post(name: Constants.Notifications.libraryDidUpdate, object: nil)
    }

    func fullRescan() {
        // Delete all existing tracks, albums, and artists
        let db = DatabaseManager.shared

        db.beginTransaction()
        db.execute(sql: "DELETE FROM playlist_tracks")
        db.execute(sql: "DELETE FROM tracks")
        db.execute(sql: "DELETE FROM albums")
        db.execute(sql: "DELETE FROM artists")
        db.execute(sql: "DELETE FROM genres")
        db.execute(sql: "DELETE FROM composers")
        db.execute(sql: "UPDATE library_paths SET last_scanned = NULL")
        db.commitTransaction()

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

    private func updateProgress(_ message: String, scanning: Bool = true) {
        DispatchQueue.main.async {
            self.scanProgress = message
            self.isScanningPublished = scanning
        }
    }

    private func updatePathStatus(path: String, state: LibraryPathStatus.ScanState) {
        DispatchQueue.main.async {
            if let idx = self.pathStatuses.firstIndex(where: { $0.path == path }) {
                let old = self.pathStatuses[idx]
                self.pathStatuses[idx] = LibraryPathStatus(
                    id: old.id, path: old.path, isAvailable: old.isAvailable,
                    isNetworkVolume: old.isNetworkVolume, scanState: state
                )
            }
        }
    }

    // MARK: - In-memory caches for scan performance (internal for TrackDAO access)
    private var _artistCache: [String: Int64] = [:]
    private var _genreCache: [String: Int64] = [:]
    private var _composerCache: [String: Int64] = [:]
    private var _albumCache: [String: Int64] = [:]  // key: "title|artistId"
    private let cacheLock = NSLock()

    func getCachedArtist(_ name: String) -> Int64? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return _artistCache[name]
    }
    func setCachedArtist(_ name: String, id: Int64) {
        cacheLock.lock()
        _artistCache[name] = id
        cacheLock.unlock()
    }
    func getCachedGenre(_ name: String) -> Int64? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return _genreCache[name]
    }
    func setCachedGenre(_ name: String, id: Int64) {
        cacheLock.lock()
        _genreCache[name] = id
        cacheLock.unlock()
    }
    func getCachedComposer(_ name: String) -> Int64? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return _composerCache[name]
    }
    func setCachedComposer(_ name: String, id: Int64) {
        cacheLock.lock()
        _composerCache[name] = id
        cacheLock.unlock()
    }
    func getCachedAlbum(_ key: String) -> Int64? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return _albumCache[key]
    }
    func setCachedAlbum(_ key: String, id: Int64) {
        cacheLock.lock()
        _albumCache[key] = id
        cacheLock.unlock()
    }

    private static let yearFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "yyyy-MM", "yyyy"].map { format in
            let f = DateFormatter()
            f.dateFormat = format
            return f
        }
    }()

    private func performScan(fullRescan: Bool) {
        scanLock.lock()
        guard !isCurrentlyScanning else {
            scanLock.unlock()
            return
        }
        isCurrentlyScanning = true
        scanLock.unlock()

        updateProgress("Preparing scan...")
        refreshPathStatuses()

        defer {
            scanLock.lock()
            isCurrentlyScanning = false
            scanLock.unlock()
            updateProgress("", scanning: false)
        }

        let paths = getLibraryPaths()
        let db = DatabaseManager.shared

        // Mark scan start time — used to detect deleted files instead of a Set
        let scanStartTime = Date().timeIntervalSince1970

        // Pre-populate entity caches from database
        cacheLock.lock()
        _artistCache.removeAll()
        for row in db.query(sql: "SELECT id, name FROM artists") {
            if let id = row["id"] as? Int64, let name = row["name"] as? String {
                _artistCache[name] = id
            }
        }
        _genreCache.removeAll()
        for row in db.query(sql: "SELECT id, name FROM genres") {
            if let id = row["id"] as? Int64, let name = row["name"] as? String {
                _genreCache[name] = id
            }
        }
        _composerCache.removeAll()
        for row in db.query(sql: "SELECT id, name FROM composers") {
            if let id = row["id"] as? Int64, let name = row["name"] as? String {
                _composerCache[name] = id
            }
        }
        _albumCache.removeAll()
        for row in db.query(sql: "SELECT id, title, artist_id FROM albums") {
            if let id = row["id"] as? Int64, let title = row["title"] as? String {
                let artistId = row["artist_id"] as? Int64
                let key = "\(title)|\(artistId ?? -1)"
                _albumCache[key] = id
            }
        }
        cacheLock.unlock()

        // Build a set of existing file paths with their modification dates for fast lookup
        var existingTracks: [String: Double] = [:]  // filePath -> dateModified
        if !fullRescan {
            let rows = db.query(sql: "SELECT file_path, date_modified FROM tracks")
            for row in rows {
                if let path = row["file_path"] as? String, let modified = row["date_modified"] as? Double {
                    existingTracks[path] = modified
                }
            }
        }

        // Disable FTS triggers during scan — rebuild index at end
        db.disableFTSTriggers()

        for libraryPath in paths {
            guard FileManager.default.fileExists(atPath: libraryPath) else {
                updatePathStatus(path: libraryPath, state: .unavailable)
                continue
            }

            let url = URL(fileURLWithPath: libraryPath)
            let isNetwork = Self.isNetworkVolume(path: libraryPath)
            let folderName = url.lastPathComponent
            updateProgress("Discovering files in \(folderName)...")
            updatePathStatus(path: libraryPath, state: .scanning(processed: 0, total: 0))

            // Stream file enumeration — process in batches without collecting all URLs first
            var totalDiscovered = 0
            var batchCount = 0
            let batchSize = 500

            db.beginTransaction()

            enumerateAudioFiles(in: url) { fileURL in
                totalDiscovered += 1

                let progressInterval = isNetwork ? 10 : 50
                if totalDiscovered % progressInterval == 0 {
                    self.updateProgress("Scanning \(folderName): \(totalDiscovered) files...")
                    self.updatePathStatus(path: libraryPath, state: .scanning(processed: totalDiscovered, total: 0))
                }

                // Use autoreleasepool to free SFBAudioEngine Obj-C objects each iteration
                autoreleasepool {
                    let filePath = fileURL.path

                    // Handle CUE files separately
                    if fileURL.pathExtension.lowercased() == "cue" {
                        self.processCUEFile(fileURL)
                        db.execute(sql: "UPDATE tracks SET last_scan_time = ? WHERE file_path LIKE ?",
                                   parameters: [scanStartTime, filePath + "%"])
                        return
                    }

                    // Mark this file as seen in current scan
                    let existingModified = existingTracks[filePath]

                    // Get file modification date
                    let fileAttributes = try? FileManager.default.attributesOfItem(atPath: filePath)
                    let modificationDate = fileAttributes?[.modificationDate] as? Date ?? Date()

                    // Skip if file hasn't been modified
                    if !fullRescan, let existingMod = existingModified {
                        if existingMod >= modificationDate.timeIntervalSince1970 {
                            // Just mark as seen
                            db.execute(sql: "UPDATE tracks SET last_scan_time = ? WHERE file_path = ?",
                                       parameters: [scanStartTime, filePath])
                            return
                        }
                    }

                    // Extract metadata and update/insert track
                    if let metadata = self.extractMetadata(from: fileURL) {
                        if existingModified != nil {
                            self.trackDAO.updateTrack(metadata: metadata, filePath: filePath)
                        } else {
                            self.trackDAO.insertTrack(metadata: metadata)
                        }
                        db.execute(sql: "UPDATE tracks SET last_scan_time = ? WHERE file_path = ?",
                                   parameters: [scanStartTime, filePath])
                    }
                }

                batchCount += 1

                // Commit transaction batch and refresh views periodically
                if batchCount >= batchSize {
                    db.commitTransaction()
                    batchCount = 0

                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Constants.Notifications.libraryDidUpdate, object: nil)
                    }

                    db.beginTransaction()
                }
            }

            // Commit remaining batch
            db.commitTransaction()

            // Update last_scanned timestamp
            let now = Date().timeIntervalSince1970
            db.execute(sql: "UPDATE library_paths SET last_scanned = ? WHERE path = ?",
                      parameters: [now, libraryPath])

            updatePathStatus(path: libraryPath, state: .complete(trackCount: totalDiscovered))
        }

        // Remove tracks that no longer exist (not seen during this scan)
        if !fullRescan {
            updateProgress("Cleaning up removed files...")
            for libraryPath in paths {
                guard FileManager.default.fileExists(atPath: libraryPath) else { continue }
                let escapedPath = libraryPath.replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                db.execute(sql: """
                    DELETE FROM tracks WHERE file_path LIKE ? ESCAPE '\\'
                    AND (last_scan_time IS NULL OR last_scan_time < ?)
                """, parameters: [escapedPath + "/%", scanStartTime])
            }
        }

        // Re-enable FTS triggers and rebuild index
        db.enableFTSTriggers()
        updateProgress("Building search index...")
        db.rebuildFTSIndex()

        // Update album and artist counts
        updateProgress("Updating library statistics...")
        updateLibraryStatistics()

        // Clear caches
        cacheLock.lock()
        _artistCache.removeAll()
        _genreCache.removeAll()
        _composerCache.removeAll()
        _albumCache.removeAll()
        cacheLock.unlock()

        // Post notification that library was updated
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Constants.Notifications.libraryDidUpdate, object: nil)
        }
    }

    /// Stream-enumerate audio files without collecting them all into an array
    private func enumerateAudioFiles(in directory: URL, handler: (URL) -> Void) {
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  let isRegularFile = resourceValues.isRegularFile,
                  isRegularFile else {
                continue
            }

            let fileExtension = fileURL.pathExtension.lowercased()
            if supportedExtensions.contains(fileExtension) || fileExtension == "cue" {
                handler(fileURL)
            }
        }
    }

    // MARK: - CUE Sheet Processing

    private func processCUEFile(_ cueURL: URL) {
        guard let sheet = CUEParser.parse(url: cueURL) else { return }

        let cueDir = cueURL.deletingLastPathComponent()
        var audioURL = cueDir.appendingPathComponent(sheet.audioFileName)

        if !FileManager.default.fileExists(atPath: audioURL.path) {
            // Fallback: look for a single audio file in the same directory
            // CUE files often reference a name that doesn't match the actual file
            if let fallback = findAudioFileForCUE(in: cueDir, cueFileName: cueURL.deletingPathExtension().lastPathComponent) {
                audioURL = fallback
            } else {
                #if DEBUG
                print("CUE: referenced audio file not found: \(audioURL.path)")
                #endif
                return
            }
        }

        // Get audio file properties for total duration
        guard let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: audioURL),
              let totalDuration = audioFile.properties.duration else {
            return
        }

        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
        let fileSize = fileAttributes?[.size] as? Int64 ?? 0
        let modificationDate = fileAttributes?[.modificationDate] as? Date ?? Date()

        for (i, cueTrack) in sheet.tracks.enumerated() {
            // Calculate end time: next track's start time, or total duration
            let endTime: TimeInterval
            if i + 1 < sheet.tracks.count {
                endTime = sheet.tracks[i + 1].startTime
            } else {
                endTime = totalDuration
            }

            let trackDuration = endTime - cueTrack.startTime

            // Use a virtual path: audiofile.flac#track01
            let virtualPath = "\(audioURL.path)#track\(String(format: "%02d", cueTrack.trackNumber))"

            // Check if already exists
            let existing = trackDAO.getTrack(byPath: virtualPath)
            if existing != nil { continue }

            var metadata = AudioMetadata(
                filePath: virtualPath,
                fileSize: fileSize,
                duration: trackDuration,
                dateModified: modificationDate
            )

            metadata.title = cueTrack.title
            metadata.artist = cueTrack.performer
            metadata.album = sheet.title
            metadata.albumArtist = sheet.performer
            metadata.trackNumber = cueTrack.trackNumber
            metadata.formatName = audioURL.pathExtension.uppercased()
            metadata.startTime = cueTrack.startTime
            metadata.endTime = endTime

            // Get technical properties from the audio file
            if let sampleRate = audioFile.properties.sampleRate {
                metadata.sampleRate = Int(sampleRate)
            }
            if let bitrate = audioFile.properties.bitrate {
                metadata.bitrate = Int(bitrate / 1000)
            }
            if let channelCount = audioFile.properties.channelCount {
                metadata.channelCount = Int(channelCount)
            }
            if let bitDepth = audioFile.properties.bitDepth {
                metadata.bitDepth = bitDepth
            }

            trackDAO.insertTrack(metadata: metadata)
        }
    }

    /// Public wrapper for re-extracting metadata after tag edits
    func reExtractMetadata(from url: URL) -> AudioMetadata? {
        return extractMetadata(from: url)
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
            #if DEBUG
            print("Failed to read audio file: \(url.path)")
            #endif
            return nil
        }

        // Get audio properties
        let properties = audioFile.properties
        guard let duration = properties.duration, duration > 0 else {
            #if DEBUG
            print("Invalid audio properties for: \(url.path)")
            #endif
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
        if let bitDepth = properties.bitDepth {
            metadata.bitDepth = bitDepth
        }

        // Format info - derive from file extension
        metadata.formatName = url.pathExtension.uppercased()

        // Use filename as title if no title metadata
        if metadata.title == nil || metadata.title?.isEmpty == true {
            metadata.title = url.deletingPathExtension().lastPathComponent
        }

        return metadata
    }

    private func extractYear(from dateString: String) -> Int? {
        for formatter in Self.yearFormatters {
            if let date = formatter.date(from: dateString) {
                return Calendar.current.component(.year, from: date)
            }
        }

        // Try to extract just the year if it's a 4-digit number
        if dateString.count >= 4 {
            return Int(String(dateString.prefix(4)))
        }

        return nil
    }

    /// Find a matching audio file for a CUE sheet when the referenced filename doesn't exist
    private func findAudioFileForCUE(in directory: URL, cueFileName: String) -> URL? {
        let audioExtensions: Set<String> = ["wav", "flac", "ape", "wv", "alac", "aiff", "aif"]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let audioFiles = contents.filter { audioExtensions.contains($0.pathExtension.lowercased()) }

        // If there's only one audio file, it's almost certainly the one the CUE references
        if audioFiles.count == 1 {
            return audioFiles[0]
        }

        // Try matching by CUE filename stem (e.g., "album.cue" -> "album.flac")
        for file in audioFiles {
            if file.deletingPathExtension().lastPathComponent.lowercased() == cueFileName.lowercased() {
                return file
            }
        }

        return nil
    }

    // removeDeletedTracks is now handled inline via last_scan_time column

    func updateLibraryStatistics() {
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
    var bitDepth: Int?

    // ReplayGain
    var replayGainTrackGain: Double?
    var replayGainAlbumGain: Double?

    // CUE sheet support
    var startTime: TimeInterval?
    var endTime: TimeInterval?
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
