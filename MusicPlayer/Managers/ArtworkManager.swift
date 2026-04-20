import Foundation
import AppKit
import SFBAudioEngine

class ArtworkManager {
    static let shared = ArtworkManager()

    // MARK: - Properties

    private let artworkQueue = DispatchQueue(label: "com.orangemusicplayer.artwork", qos: .utility, attributes: .concurrent)
    private let memoryCache = NSCache<NSString, NSImage>()
    private let cacheLock = NSLock()

    private let musicBrainzBaseURL = "https://musicbrainz.org/ws/2"
    private let coverArtArchiveURL = "https://coverartarchive.org"
    private let smallImageSize: CGFloat = 300

    // Rate limiting for MusicBrainz (1 request per second as per their guidelines)
    private var lastMusicBrainzRequest: Date?
    private let rateLimitLock = NSLock()
    private let musicBrainzRateLimit: TimeInterval = 1.0

    // Concurrency limiting semaphore — allows up to 4 concurrent artwork loads
    private let concurrencySemaphore = DispatchSemaphore(value: 4)

    // MARK: - Initialization

    private init() {
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    // MARK: - Public API - Album Artwork

    /// Fetch artwork for an album
    func fetchAlbumArtwork(for album: Album, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        fetchAlbumArtwork(albumTitle: album.title, artistName: album.artistName, completion: completion)
    }

    // MARK: - Async API (preferred for SwiftUI)

    /// Async wrapper for album artwork — supports Task cancellation
    func fetchAlbumArtwork(for album: Album) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            fetchAlbumArtwork(for: album) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Async wrapper for artist artwork — supports Task cancellation
    func fetchArtistArtwork(for artist: Artist) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            fetchArtistArtwork(for: artist) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Fetch artwork for an album by title and artist
    func fetchAlbumArtwork(albumTitle: String, artistName: String?, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        // Generate cache key and check memory cache immediately (fast path, no queue needed)
        let cacheKey = self.generateCacheKey(type: .album, name: albumTitle, artist: artistName)

        if let cachedImage = self.getCachedImage(for: cacheKey) {
            DispatchQueue.main.async { completion(.success(cachedImage)) }
            return
        }

        artworkQueue.async { [weak self] in
            guard let self = self else { return }

            // Re-check memory cache (may have been populated while queued)
            if let cachedImage = self.getCachedImage(for: cacheKey) {
                self.callCompletion(completion, with: .success(cachedImage))
                return
            }

            // Acquire semaphore to limit concurrent heavy work
            self.concurrencySemaphore.wait()
            defer { self.concurrencySemaphore.signal() }

            // Check disk cache
            if let diskCachedImage = self.loadImageFromDisk(cacheKey: cacheKey) {
                self.cacheImage(diskCachedImage, for: cacheKey)
                self.callCompletion(completion, with: .success(diskCachedImage))
                return
            }

            // Check for folder image (cover.jpg etc) using album tracks
            if let folderImage = self.findFolderArtwork(albumTitle: albumTitle, artistName: artistName) {
                if let resizedImage = self.resizeImage(folderImage, to: self.smallImageSize) {
                    self.cacheImage(resizedImage, for: cacheKey)
                    self.saveImageToDisk(image: resizedImage, cacheKey: cacheKey)
                    self.callCompletion(completion, with: .success(resizedImage))
                    return
                }
            }

            // Fetch from MusicBrainz
            self.fetchAlbumArtworkFromMusicBrainz(albumTitle: albumTitle, artistName: artistName) { result in
                switch result {
                case .success(let image):
                    if let resizedImage = self.resizeImage(image, to: self.smallImageSize) {
                        self.cacheImage(resizedImage, for: cacheKey)
                        self.saveImageToDisk(image: resizedImage, cacheKey: cacheKey)
                        self.callCompletion(completion, with: .success(resizedImage))
                    } else {
                        self.callCompletion(completion, with: .failure(.processingError))
                    }

                case .failure(let error):
                    self.callCompletion(completion, with: .failure(error))
                }
            }
        }
    }

    /// Fetch artwork from track file metadata
    func fetchArtworkFromTrack(_ track: Track, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        // First check if we already have cached album artwork — ensures consistency
        // between album detail view and now playing panel
        if let albumTitle = track.albumTitle {
            let artistName = track.albumArtistName ?? track.artistName
            let cacheKey = self.generateCacheKey(type: .album, name: albumTitle, artist: artistName)
            if let cachedImage = self.getCachedImage(for: cacheKey) {
                DispatchQueue.main.async { completion(.success(cachedImage)) }
                return
            }
        }

        artworkQueue.async { [weak self] in
            guard let self = self else { return }

            // Re-check album cache (may have been populated while queued)
            if let albumTitle = track.albumTitle {
                let artistName = track.albumArtistName ?? track.artistName
                let cacheKey = self.generateCacheKey(type: .album, name: albumTitle, artist: artistName)
                if let cachedImage = self.getCachedImage(for: cacheKey) {
                    self.callCompletion(completion, with: .success(cachedImage))
                    return
                }
                // Check disk cache for album art
                if let diskImage = self.loadImageFromDisk(cacheKey: cacheKey) {
                    self.cacheImage(diskImage, for: cacheKey)
                    self.callCompletion(completion, with: .success(diskImage))
                    return
                }
            }

            let url = URL(fileURLWithPath: track.filePath)

            guard let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: url) else {
                self.callCompletion(completion, with: .failure(.noMetadata))
                return
            }

            let metadata = audioFile.metadata

            // Try to get attached pictures
            let attachedPictures = metadata.attachedPictures
            if let firstPicture = attachedPictures.first {
                let imageData = firstPicture.imageData

                if let image = NSImage(data: imageData) {

                    // Resize and cache
                    if let resizedImage = self.resizeImage(image, to: self.smallImageSize) {
                        // Cache using album info
                        if let albumTitle = track.albumTitle, let artistName = track.albumArtistName ?? track.artistName {
                            let cacheKey = self.generateCacheKey(type: .album, name: albumTitle, artist: artistName)
                            self.cacheImage(resizedImage, for: cacheKey)
                            self.saveImageToDisk(image: resizedImage, cacheKey: cacheKey)
                        }

                        self.callCompletion(completion, with: .success(resizedImage))
                    } else {
                        self.callCompletion(completion, with: .failure(.processingError))
                    }
                    return
                }
            }

            self.callCompletion(completion, with: .failure(.noMetadata))
        }
    }

    // MARK: - Public API - Artist Artwork

    /// Fetch artwork for an artist
    func fetchArtistArtwork(for artist: Artist, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        fetchArtistArtwork(artistName: artist.name, completion: completion)
    }

    /// Fetch artwork for an artist by name
    func fetchArtistArtwork(artistName: String, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        // Fast path: check memory cache without hitting the queue
        let cacheKey = self.generateCacheKey(type: .artist, name: artistName, artist: nil)

        if let cachedImage = self.getCachedImage(for: cacheKey) {
            DispatchQueue.main.async { completion(.success(cachedImage)) }
            return
        }

        artworkQueue.async { [weak self] in
            guard let self = self else { return }

            // Re-check memory cache
            if let cachedImage = self.getCachedImage(for: cacheKey) {
                self.callCompletion(completion, with: .success(cachedImage))
                return
            }

            self.concurrencySemaphore.wait()
            defer { self.concurrencySemaphore.signal() }

            // Check disk cache
            if let diskCachedImage = self.loadImageFromDisk(cacheKey: cacheKey) {
                self.cacheImage(diskCachedImage, for: cacheKey)
                self.callCompletion(completion, with: .success(diskCachedImage))
                return
            }

            // Fetch from MusicBrainz
            self.fetchArtistArtworkFromMusicBrainz(artistName: artistName) { result in
                switch result {
                case .success(let image):
                    if let resizedImage = self.resizeImage(image, to: self.smallImageSize) {
                        self.cacheImage(resizedImage, for: cacheKey)
                        self.saveImageToDisk(image: resizedImage, cacheKey: cacheKey)
                        self.callCompletion(completion, with: .success(resizedImage))
                    } else {
                        self.callCompletion(completion, with: .failure(.processingError))
                    }

                case .failure(let error):
                    self.callCompletion(completion, with: .failure(error))
                }
            }
        }
    }

    // MARK: - Cache Management

    /// Clear memory cache
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    /// Clear disk cache
    func clearDiskCache() {
        let cacheDir = getCacheDirectory()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Clear all caches
    func clearAllCaches() {
        clearMemoryCache()
        clearDiskCache()
    }

    // MARK: - Folder Artwork Lookup

    private static let folderArtworkNames = [
        "cover", "folder", "front", "album", "artwork", "art"
    ]
    private static let imageExtensions = ["jpg", "jpeg", "png"]

    /// Search for cover.jpg, folder.jpg, front.jpg etc. in the directory of album tracks
    private func findFolderArtwork(albumTitle: String, artistName: String?) -> NSImage? {
        // Get a track from this album to find the directory
        let trackDAO = TrackDAO()
        let albumDAO = AlbumDAO()

        // Find the album to get its ID
        let albums = albumDAO.search(query: albumTitle)
        guard let album = albums.first(where: { $0.artistName == artistName || artistName == nil }) else {
            return nil
        }

        let tracks = trackDAO.getByAlbumId(albumId: album.id)
        guard let firstTrack = tracks.first else { return nil }

        let directory = URL(fileURLWithPath: firstTrack.filePath).deletingLastPathComponent()
        return findFolderArtwork(in: directory)
    }

    /// Search for artwork image files in a specific directory
    func findFolderArtwork(in directory: URL) -> NSImage? {
        let fm = FileManager.default
        for name in Self.folderArtworkNames {
            for ext in Self.imageExtensions {
                let fileURL = directory.appendingPathComponent("\(name).\(ext)")
                if fm.fileExists(atPath: fileURL.path), let image = NSImage(contentsOf: fileURL) {
                    return image
                }
            }
        }
        // Also check case-insensitive by listing directory
        if let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for fileURL in contents {
                let name = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                let ext = fileURL.pathExtension.lowercased()
                if Self.imageExtensions.contains(ext) && Self.folderArtworkNames.contains(name) {
                    if let image = NSImage(contentsOf: fileURL) {
                        return image
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Save Artwork

    /// Save artwork for an album — writes cover.jpg to album folder or embeds in track metadata
    func saveArtwork(for album: Album, image: NSImage) {
        let trackDAO = TrackDAO()
        let tracks = trackDAO.getByAlbumId(albumId: album.id)
        guard !tracks.isEmpty else { return }

        // Determine if all tracks share the same parent directory
        let directories = Set(tracks.map { URL(fileURLWithPath: $0.filePath).deletingLastPathComponent().path })

        if directories.count == 1, let dir = directories.first {
            // All tracks in one folder — write cover.jpg
            let coverURL = URL(fileURLWithPath: dir).appendingPathComponent("cover.jpg")
            if let jpegData = imageToJPEGData(image, quality: 0.9) {
                do {
                    // Access security-scoped bookmark if needed
                    let dirURL = URL(fileURLWithPath: dir)
                    let accessing = dirURL.startAccessingSecurityScopedResource()
                    defer { if accessing { dirURL.stopAccessingSecurityScopedResource() } }

                    try jpegData.write(to: coverURL)
                    #if DEBUG
                    print("Saved cover.jpg to \(dir)")
                    #endif
                } catch {
                    #if DEBUG
                    print("Failed to write cover.jpg: \(error). Falling back to metadata embedding.")
                    #endif
                    embedArtworkInTracks(image: image, tracks: tracks)
                }
            }
        } else {
            // Tracks scattered — embed in each file's metadata
            embedArtworkInTracks(image: image, tracks: tracks)
        }

        // Clear cache for this album and re-cache
        let cacheKey = generateCacheKey(type: .album, name: album.title, artist: album.artistName)
        memoryCache.removeObject(forKey: cacheKey as NSString)
        let fileURL = getCacheFileURL(for: cacheKey)
        try? FileManager.default.removeItem(at: fileURL)

        // Cache resized version
        if let resized = resizeImage(image, to: smallImageSize) {
            cacheImage(resized, for: cacheKey)
            saveImageToDisk(image: resized, cacheKey: cacheKey)
        }

        // Notify
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Constants.Notifications.artworkDidChange,
                object: nil,
                userInfo: ["albumId": album.id]
            )
        }
    }

    private func embedArtworkInTracks(image: NSImage, tracks: [Track]) {
        guard let jpegData = imageToJPEGData(image, quality: 0.9) else { return }

        for track in tracks {
            let url = URL(fileURLWithPath: track.filePath)
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            guard let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: url) else { continue }

            let picture = AttachedPicture(imageData: jpegData, type: .frontCover, description: "Front Cover")
            audioFile.metadata.removeAllAttachedPictures()
            audioFile.metadata.attachPicture(picture)

            do {
                try audioFile.writeMetadata()
            } catch {
                #if DEBUG
                print("Failed to embed artwork in \(track.filePath): \(error)")
                #endif
            }
        }
    }

    private func imageToJPEGData(_ image: NSImage, quality: CGFloat) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Clear cached artwork for a specific album
    func clearAlbumCache(albumTitle: String, artistName: String?) {
        let cacheKey = generateCacheKey(type: .album, name: albumTitle, artist: artistName)
        memoryCache.removeObject(forKey: cacheKey as NSString)
        let fileURL = getCacheFileURL(for: cacheKey)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Private Methods - MusicBrainz API

    private func fetchAlbumArtworkFromMusicBrainz(albumTitle: String, artistName: String?, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        // Step 1: Search for the release
        searchMusicBrainzRelease(albumTitle: albumTitle, artistName: artistName) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let releaseId):
                // Step 2: Fetch artwork from Cover Art Archive
                self.fetchCoverArt(releaseId: releaseId, completion: completion)

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func searchMusicBrainzRelease(albumTitle: String, artistName: String?, completion: @escaping (Result<String, ArtworkError>) -> Void) {
        // Build search query
        var query = "release:\"\(albumTitle)\""
        if let artist = artistName {
            query += " AND artist:\"\(artist)\""
        }

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(.failure(.invalidQuery))
            return
        }

        // Construct search URL
        guard let searchURL = URL(string: "\(musicBrainzBaseURL)/release/?query=\(encodedQuery)&fmt=json") else {
            completion(.failure(.invalidURL))
            return
        }

        // Rate limiting (non-blocking)
        scheduleAfterRateLimit(on: artworkQueue) { [weak self] in
            guard let self = self else { return }

            // Create request with User-Agent (required by MusicBrainz)
            var request = URLRequest(url: searchURL)
            request.setValue("\(Constants.musicBrainzAppName)/\(Constants.musicBrainzVersion) ( \(Constants.musicBrainzContact) )", forHTTPHeaderField: "User-Agent")

            // Perform search request
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                #if DEBUG
                print("MusicBrainz search error: \(error)")
                #endif
                completion(.failure(.networkError(error)))
                return
            }

            guard let data = data else {
                completion(.failure(.noData))
                return
            }

            // Parse search results
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let releases = json["releases"] as? [[String: Any]],
                   let firstRelease = releases.first,
                   let releaseId = firstRelease["id"] as? String {

                    completion(.success(releaseId))
                } else {
                    completion(.failure(.noResults))
                }
            } catch {
                #if DEBUG
                print("JSON parsing error: \(error)")
                #endif
                completion(.failure(.parsingError))
            }
        }

        task.resume()
        } // scheduleAfterRateLimit
    }

    private func fetchCoverArt(releaseId: String, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        guard let artworkURL = URL(string: "\(coverArtArchiveURL)/release/\(releaseId)/front-500") else {
            completion(.failure(.invalidURL))
            return
        }


        let task = URLSession.shared.dataTask(with: artworkURL) { data, response, error in
            if let error = error {
                #if DEBUG
                print("Cover art download error: \(error)")
                #endif
                completion(.failure(.networkError(error)))
                return
            }

            guard let data = data, let image = NSImage(data: data) else {
                completion(.failure(.noData))
                return
            }

            completion(.success(image))
        }

        task.resume()
    }

    private func fetchArtistArtworkFromMusicBrainz(artistName: String, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        // Step 1: Search for artist on MusicBrainz to get MBID
        let artistEncoded = artistName.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""
        guard let searchURL = URL(string: "https://musicbrainz.org/ws/2/artist/?query=\(artistEncoded)&fmt=json") else {
            completion(.failure(.invalidURL))
            return
        }

        // Rate limiting (non-blocking)
        scheduleAfterRateLimit(on: artworkQueue) { [weak self] in
            guard let self = self else { return }

            var request = URLRequest(url: searchURL)
            request.setValue("\(Constants.musicBrainzAppName)/\(Constants.musicBrainzVersion) ( \(Constants.musicBrainzContact) )", forHTTPHeaderField: "User-Agent")

            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }

                if let error = error {
                    #if DEBUG
                    print("MusicBrainz artist search error: \(error)")
                    #endif
                    self.callCompletion(completion, with: .failure(.networkError(error)))
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let artists = json["artists"] as? [[String: Any]],
                      let firstArtist = artists.first,
                      let mbid = firstArtist["id"] as? String else {
                    #if DEBUG
                    print("No artist found on MusicBrainz for: \(artistName)")
                    #endif
                    self.callCompletion(completion, with: .failure(.noResults))
                    return
                }

                // Step 2: Try to get artist image from Fanart.tv using MBID
                self.fetchArtistImageFromFanartTV(mbid: mbid) { result in
                    switch result {
                    case .success(let image):
                        self.callCompletion(completion, with: .success(image))
                    case .failure:
                        // Step 3: Fallback to TheAudioDB
                        #if DEBUG
                        print("Fanart.tv failed, trying TheAudioDB...")
                        #endif
                        self.fetchArtistImageFromTheAudioDB(artist: artistName, completion: completion)
                    }
                }
            }.resume()
        } // scheduleAfterRateLimit
    }
    
    private func fetchArtistImageFromFanartTV(mbid: String, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        // Fanart.tv free tier doesn't require API key for basic usage
        let urlString = "https://webservice.fanart.tv/v3/music/\(mbid)"
        guard let url = URL(string: urlString) else {
            completion(.failure(.invalidURL))
            return
        }

        let request = URLRequest(url: url)
        // Optional: Add API key if you have one for better rate limits
        // If you have an API key: var request = URLRequest(url: url)
        // request.setValue("YOUR_API_KEY", forHTTPHeaderField: "api-key")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                #if DEBUG
                print("Fanart.tv error: \(error)")
                #endif
                self.callCompletion(completion, with: .failure(.networkError(error)))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                #if DEBUG
                print("Failed to parse Fanart.tv response")
                #endif
                self.callCompletion(completion, with: .failure(.parsingError))
                return
            }

            // Try artistthumb first (best quality)
            if let artistthumbs = json["artistthumb"] as? [[String: Any]],
               let firstThumb = artistthumbs.first,
               let imageURL = firstThumb["url"] as? String,
               let url = URL(string: imageURL) {
                self.downloadAndProcessImage(from: url, completion: completion)
                return
            }

            // Fallback to hdmusiclogo or other image types
            if let logos = json["hdmusiclogo"] as? [[String: Any]],
               let firstLogo = logos.first,
               let imageURL = firstLogo["url"] as? String,
               let url = URL(string: imageURL) {
                self.downloadAndProcessImage(from: url, completion: completion)
                return
            }

            #if DEBUG
            print("No artist images found on Fanart.tv")
            #endif
            self.callCompletion(completion, with: .failure(.noResults))
        }.resume()
    }
    
    private func fetchArtistImageFromTheAudioDB(artist: String, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        // TheAudioDB free API
        let artistEncoded = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://www.theaudiodb.com/api/v1/json/2/search.php?s=\(artistEncoded)"

        guard let url = URL(string: urlString) else {
            completion(.failure(.invalidURL))
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                #if DEBUG
                print("TheAudioDB error: \(error)")
                #endif
                self.callCompletion(completion, with: .failure(.networkError(error)))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let artists = json["artists"] as? [[String: Any]],
                  let firstArtist = artists.first else {
                #if DEBUG
                print("No artist found on TheAudioDB for: \(artist)")
                #endif
                self.callCompletion(completion, with: .failure(.noResults))
                return
            }

            // Try different image fields in order of preference
            let imageFields = ["strArtistThumb", "strArtistFanart", "strArtistBanner"]

            for field in imageFields {
                if let imageURLString = firstArtist[field] as? String,
                   !imageURLString.isEmpty,
                   let imageURL = URL(string: imageURLString) {
                    self.downloadAndProcessImage(from: imageURL, completion: completion)
                    return
                }
            }

            #if DEBUG
            print("No artist images found on TheAudioDB")
            #endif
            self.callCompletion(completion, with: .failure(.noResults))
        }.resume()
    }
    
    private func downloadAndProcessImage(from url: URL, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                #if DEBUG
                print("Image download error: \(error)")
                #endif
                self.callCompletion(completion, with: .failure(.networkError(error)))
                return
            }

            guard let data = data, let image = NSImage(data: data) else {
                #if DEBUG
                print("Failed to create image from data")
                #endif
                self.callCompletion(completion, with: .failure(.noData))
                return
            }

            // Resize the image
            if let resizedImage = self.resizeImage(image, to: self.smallImageSize) {
                self.callCompletion(completion, with: .success(resizedImage))
            } else {
                #if DEBUG
                print("Failed to resize image")
                #endif
                self.callCompletion(completion, with: .failure(.processingError))
            }
        }.resume()
    }

    // MARK: - Private Methods - Image Processing

    func resizeImage(_ image: NSImage, to maxSize: CGFloat) -> NSImage? {
        let originalSize = image.size

        // Calculate new size maintaining aspect ratio
        let widthRatio = maxSize / originalSize.width
        let heightRatio = maxSize / originalSize.height
        let ratio = min(widthRatio, heightRatio)

        let newSize = NSSize(width: originalSize.width * ratio, height: originalSize.height * ratio)

        // Create resized image
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()

        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .copy,
                   fraction: 1.0)

        resizedImage.unlockFocus()

        return resizedImage
    }

    // MARK: - Private Methods - Caching

    private func generateCacheKey(type: ArtworkType, name: String, artist: String?) -> String {
        let sanitizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedArtist = (artist ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let key: String
        switch type {
        case .album:
            key = "album-\(sanitizedArtist)-\(sanitizedName)"
        case .artist:
            key = "artist-\(sanitizedName)"
        }

        return key.replacingOccurrences(of: " ", with: "_")
    }

    private func getCachedImage(for key: String) -> NSImage? {
        return memoryCache.object(forKey: key as NSString)
    }

    private func cacheImage(_ image: NSImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    private func getCacheDirectory() -> URL {
        let cacheDir = FileManager.default.cacheDirectory(for: Constants.artworkCacheDirectory)
        return cacheDir
    }

    private func getCacheFileURL(for key: String) -> URL {
        let cacheDir = getCacheDirectory()
        let filename = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return cacheDir.appendingPathComponent("\(filename).png")
    }

    private func loadImageFromDisk(cacheKey: String) -> NSImage? {
        let fileURL = getCacheFileURL(for: cacheKey)

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let image = NSImage(contentsOf: fileURL) else {
            return nil
        }

        return image
    }

    private func saveImageToDisk(image: NSImage, cacheKey: String) {
        let fileURL = getCacheFileURL(for: cacheKey)

        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            #if DEBUG
            print("Failed to convert image to PNG")
            #endif
            return
        }

        do {
            try pngData.write(to: fileURL)
        } catch {
            #if DEBUG
            print("Failed to save artwork to disk: \(error)")
            #endif
        }
    }

    // MARK: - Helper Methods

    /// Schedule work after MusicBrainz rate limit delay (non-blocking)
    private func scheduleAfterRateLimit(on queue: DispatchQueue, work: @escaping () -> Void) {
        rateLimitLock.lock()
        let delay: TimeInterval
        if let lastRequest = lastMusicBrainzRequest {
            let elapsed = Date().timeIntervalSince(lastRequest)
            delay = max(0, musicBrainzRateLimit - elapsed)
        } else {
            delay = 0
        }
        lastMusicBrainzRequest = Date().addingTimeInterval(delay)
        rateLimitLock.unlock()
        if delay > 0 {
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            work()
        }
    }

    private func callCompletion<T>(_ completion: @escaping (Result<T, ArtworkError>) -> Void, with result: Result<T, ArtworkError>) {
        DispatchQueue.main.async {
            completion(result)
        }
    }
}

// MARK: - Supporting Types

enum ArtworkType {
    case album
    case artist
}

enum ArtworkError: Error, LocalizedError {
    case invalidQuery
    case invalidURL
    case networkError(Error)
    case noData
    case parsingError
    case noResults
    case noMetadata
    case processingError

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Invalid search query"
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .noData:
            return "No data received"
        case .parsingError:
            return "Failed to parse response"
        case .noResults:
            return "No artwork found"
        case .noMetadata:
            return "No metadata found in file"
        case .processingError:
            return "Failed to process image"
        }
    }
}
