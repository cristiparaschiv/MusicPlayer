import Foundation
import AppKit
import SFBAudioEngine

class ArtworkManager {
    static let shared = ArtworkManager()

    // MARK: - Properties

    private let artworkQueue = DispatchQueue(label: "com.orangemusicplayer.artwork", qos: .utility)
    private var memoryCache: [String: NSImage] = [:]
    private let cacheLock = NSLock()

    private let musicBrainzBaseURL = "https://musicbrainz.org/ws/2"
    private let coverArtArchiveURL = "https://coverartarchive.org"
    private let smallImageSize: CGFloat = 300

    // Rate limiting for MusicBrainz (1 request per second as per their guidelines)
    private var lastMusicBrainzRequest: Date?
    private let musicBrainzRateLimit: TimeInterval = 1.0

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API - Album Artwork

    /// Fetch artwork for an album
    func fetchAlbumArtwork(for album: Album, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        fetchAlbumArtwork(albumTitle: album.title, artistName: album.artistName, completion: completion)
    }

    /// Fetch artwork for an album by title and artist
    func fetchAlbumArtwork(albumTitle: String, artistName: String?, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        artworkQueue.async { [weak self] in
            guard let self = self else { return }

            // Generate cache key
            let cacheKey = self.generateCacheKey(type: .album, name: albumTitle, artist: artistName)

            // Check memory cache
            if let cachedImage = self.getCachedImage(for: cacheKey) {
                print("Album artwork found in memory cache for: \(albumTitle)")
                self.callCompletion(completion, with: .success(cachedImage))
                return
            }

            // Check disk cache
            if let diskCachedImage = self.loadImageFromDisk(cacheKey: cacheKey) {
                print("Album artwork found in disk cache for: \(albumTitle)")
                self.cacheImage(diskCachedImage, for: cacheKey)
                self.callCompletion(completion, with: .success(diskCachedImage))
                return
            }

            // Fetch from MusicBrainz
            print("Fetching album artwork from MusicBrainz for: \(albumTitle) by \(artistName ?? "Unknown")")
            self.fetchAlbumArtworkFromMusicBrainz(albumTitle: albumTitle, artistName: artistName) { result in
                switch result {
                case .success(let image):
                    // Resize and cache the image
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
        artworkQueue.async { [weak self] in
            guard let self = self else { return }

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
                    print("Extracted artwork from track metadata: \(track.title)")

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
        artworkQueue.async { [weak self] in
            guard let self = self else { return }

            // Generate cache key
            let cacheKey = self.generateCacheKey(type: .artist, name: artistName, artist: nil)

            // Check memory cache
            if let cachedImage = self.getCachedImage(for: cacheKey) {
                print("Artist artwork found in memory cache for: \(artistName)")
                self.callCompletion(completion, with: .success(cachedImage))
                return
            }

            // Check disk cache
            if let diskCachedImage = self.loadImageFromDisk(cacheKey: cacheKey) {
                print("Artist artwork found in disk cache for: \(artistName)")
                self.cacheImage(diskCachedImage, for: cacheKey)
                self.callCompletion(completion, with: .success(diskCachedImage))
                return
            }

            // Fetch from MusicBrainz
            print("Fetching artist artwork from MusicBrainz for: \(artistName)")
            self.fetchArtistArtworkFromMusicBrainz(artistName: artistName) { result in
                switch result {
                case .success(let image):
                    // Resize and cache the image
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
        cacheLock.lock()
        memoryCache.removeAll()
        cacheLock.unlock()
        print("Artwork memory cache cleared")
    }

    /// Clear disk cache
    func clearDiskCache() {
        let cacheDir = getCacheDirectory()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        print("Artwork disk cache cleared")
    }

    /// Clear all caches
    func clearAllCaches() {
        clearMemoryCache()
        clearDiskCache()
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

        // Rate limiting
        waitForRateLimit()

        print("Searching MusicBrainz: \(searchURL.absoluteString)")

        // Create request with User-Agent (required by MusicBrainz)
        var request = URLRequest(url: searchURL)
        request.setValue("\(Constants.musicBrainzAppName)/\(Constants.musicBrainzVersion) ( \(Constants.musicBrainzContact) )", forHTTPHeaderField: "User-Agent")

        // Perform search request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("MusicBrainz search error: \(error)")
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

                    print("Found release ID: \(releaseId)")
                    completion(.success(releaseId))
                } else {
                    completion(.failure(.noResults))
                }
            } catch {
                print("JSON parsing error: \(error)")
                completion(.failure(.parsingError))
            }
        }

        task.resume()
    }

    private func fetchCoverArt(releaseId: String, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        guard let artworkURL = URL(string: "\(coverArtArchiveURL)/release/\(releaseId)/front-500") else {
            completion(.failure(.invalidURL))
            return
        }

        print("Fetching cover art: \(artworkURL.absoluteString)")

        let task = URLSession.shared.dataTask(with: artworkURL) { data, response, error in
            if let error = error {
                print("Cover art download error: \(error)")
                completion(.failure(.networkError(error)))
                return
            }

            guard let data = data, let image = NSImage(data: data) else {
                completion(.failure(.noData))
                return
            }

            print("Successfully downloaded cover art")
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

        // Rate limiting
        waitForRateLimit()

        var request = URLRequest(url: searchURL)
        request.setValue("\(Constants.musicBrainzAppName)/\(Constants.musicBrainzVersion) ( \(Constants.musicBrainzContact) )", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("MusicBrainz artist search error: \(error)")
                self.callCompletion(completion, with: .failure(.networkError(error)))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let artists = json["artists"] as? [[String: Any]],
                  let firstArtist = artists.first,
                  let mbid = firstArtist["id"] as? String else {
                print("No artist found on MusicBrainz for: \(artistName)")
                self.callCompletion(completion, with: .failure(.noResults))
                return
            }

            print("Found artist MBID: \(mbid)")

            // Step 2: Try to get artist image from Fanart.tv using MBID
            self.fetchArtistImageFromFanartTV(mbid: mbid) { result in
                switch result {
                case .success(let image):
                    self.callCompletion(completion, with: .success(image))
                case .failure:
                    // Step 3: Fallback to TheAudioDB
                    print("Fanart.tv failed, trying TheAudioDB...")
                    self.fetchArtistImageFromTheAudioDB(artist: artistName, completion: completion)
                }
            }
        }.resume()
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
                print("Fanart.tv error: \(error)")
                self.callCompletion(completion, with: .failure(.networkError(error)))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Failed to parse Fanart.tv response")
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

            print("No artist images found on Fanart.tv")
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
                print("TheAudioDB error: \(error)")
                self.callCompletion(completion, with: .failure(.networkError(error)))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let artists = json["artists"] as? [[String: Any]],
                  let firstArtist = artists.first else {
                print("No artist found on TheAudioDB for: \(artist)")
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

            print("No artist images found on TheAudioDB")
            self.callCompletion(completion, with: .failure(.noResults))
        }.resume()
    }
    
    private func downloadAndProcessImage(from url: URL, completion: @escaping (Result<NSImage, ArtworkError>) -> Void) {
        print("Downloading image from: \(url.absoluteString)")

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("Image download error: \(error)")
                self.callCompletion(completion, with: .failure(.networkError(error)))
                return
            }

            guard let data = data, let image = NSImage(data: data) else {
                print("Failed to create image from data")
                self.callCompletion(completion, with: .failure(.noData))
                return
            }

            // Resize the image
            if let resizedImage = self.resizeImage(image, to: self.smallImageSize) {
                print("Successfully downloaded and resized image")
                self.callCompletion(completion, with: .success(resizedImage))
            } else {
                print("Failed to resize image")
                self.callCompletion(completion, with: .failure(.processingError))
            }
        }.resume()
    }

    // MARK: - Private Methods - Image Processing

    private func resizeImage(_ image: NSImage, to maxSize: CGFloat) -> NSImage? {
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
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return memoryCache[key]
    }

    private func cacheImage(_ image: NSImage, for key: String) {
        cacheLock.lock()
        memoryCache[key] = image
        cacheLock.unlock()
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
            print("Failed to convert image to PNG")
            return
        }

        do {
            try pngData.write(to: fileURL)
            print("Saved artwork to disk: \(fileURL.lastPathComponent)")
        } catch {
            print("Failed to save artwork to disk: \(error)")
        }
    }

    // MARK: - Helper Methods

    private func waitForRateLimit() {
        if let lastRequest = lastMusicBrainzRequest {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < musicBrainzRateLimit {
                let waitTime = musicBrainzRateLimit - timeSinceLastRequest
                Thread.sleep(forTimeInterval: waitTime)
            }
        }
        lastMusicBrainzRequest = Date()
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
