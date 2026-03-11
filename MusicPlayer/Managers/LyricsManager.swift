import Foundation

class LyricsManager {
    static let shared = LyricsManager()

    // MARK: - Properties

    private let lyricsQueue = DispatchQueue(label: "com.orangemusicplayer.lyrics", qos: .utility)
    private var memoryCache: [String: String] = [:]
    private let cacheLock = NSLock()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Fetch lyrics for a track
    /// Priority: cache → lrclib → embedded metadata → no lyrics
    func fetchLyrics(for track: Track, completion: @escaping (Result<String, LyricsError>) -> Void) {
        let artist = track.artistName ?? track.albumArtistName
        let embedded = track.lyrics

        lyricsQueue.async { [weak self] in
            guard let self = self else { return }

            let cacheKey = self.generateCacheKey(title: track.title, artist: artist)

            // Check memory cache
            if let cached = self.getCachedLyrics(for: cacheKey) {
                self.callCompletion(completion, with: .success(cached))
                return
            }

            // Check disk cache
            if let diskCached = self.loadLyricsFromDisk(cacheKey: cacheKey) {
                self.cacheLyrics(diskCached, for: cacheKey)
                self.callCompletion(completion, with: .success(diskCached))
                return
            }

            // Try LRCLIB (prefers synced lyrics)
            self.fetchFromLRCLIB(title: track.title, artist: artist) { result in
                switch result {
                case .success(let lyrics):
                    self.cacheLyrics(lyrics, for: cacheKey)
                    self.saveLyricsToDisk(lyrics: lyrics, cacheKey: cacheKey)
                    self.callCompletion(completion, with: .success(lyrics))
                case .failure:
                    // Fallback to embedded metadata lyrics
                    if let embedded = embedded, !embedded.isEmpty {
                        self.callCompletion(completion, with: .success(embedded))
                    } else {
                        self.callCompletion(completion, with: .failure(.noResults))
                    }
                }
            }
        }
    }

    /// Fetch lyrics by title and artist
    func fetchLyrics(title: String, artist: String?, completion: @escaping (Result<String, LyricsError>) -> Void) {
        lyricsQueue.async { [weak self] in
            guard let self = self else { return }

            // Generate cache key
            let cacheKey = self.generateCacheKey(title: title, artist: artist)

            // Check memory cache
            if let cachedLyrics = self.getCachedLyrics(for: cacheKey) {
                self.callCompletion(completion, with: .success(cachedLyrics))
                return
            }

            // Check disk cache
            if let diskCachedLyrics = self.loadLyricsFromDisk(cacheKey: cacheKey) {
                self.cacheLyrics(diskCachedLyrics, for: cacheKey)
                self.callCompletion(completion, with: .success(diskCachedLyrics))
                return
            }

            // Try LRCLIB (free, legal lyrics API)
            self.fetchFromLRCLIB(title: title, artist: artist) { result in
                switch result {
                case .success(let lyrics):
                    self.cacheLyrics(lyrics, for: cacheKey)
                    self.saveLyricsToDisk(lyrics: lyrics, cacheKey: cacheKey)
                    self.callCompletion(completion, with: .success(lyrics))
                case .failure:
                    self.callCompletion(completion, with: .failure(.noResults))
                }
            }
        }
    }

    // MARK: - LRCLIB Integration

    private func fetchFromLRCLIB(title: String, artist: String?, completion: @escaping (Result<String, LyricsError>) -> Void) {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist ?? "")
        ]

        guard let url = components.url else {
            completion(.failure(.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("OrangeMusicPlayer/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }

            guard let data = data else {
                completion(.failure(.noData))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Prefer synced lyrics, fall back to plain lyrics
                    if let syncedLyrics = json["syncedLyrics"] as? String, !syncedLyrics.isEmpty {
                        completion(.success(syncedLyrics))
                    } else if let plainLyrics = json["plainLyrics"] as? String, !plainLyrics.isEmpty {
                        completion(.success(plainLyrics))
                    } else {
                        completion(.failure(.noResults))
                    }
                } else {
                    completion(.failure(.noResults))
                }
            } catch {
                completion(.failure(.parsingError))
            }
        }.resume()
    }

    /// Clear memory cache
    func clearMemoryCache() {
        cacheLock.lock()
        memoryCache.removeAll()
        cacheLock.unlock()
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

    // MARK: - Private Methods - Caching

    private func generateCacheKey(title: String, artist: String?) -> String {
        let sanitizedTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedArtist = (artist ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(sanitizedArtist)-\(sanitizedTitle)".replacingOccurrences(of: " ", with: "_")
    }

    private func getCachedLyrics(for key: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return memoryCache[key]
    }

    private func cacheLyrics(_ lyrics: String, for key: String) {
        cacheLock.lock()
        memoryCache[key] = lyrics
        cacheLock.unlock()
    }

    private func getCacheDirectory() -> URL {
        let cacheDir = FileManager.default.cacheDirectory(for: Constants.lyricsCacheDirectory)
        return cacheDir
    }

    private func getCacheFileURL(for key: String) -> URL {
        let cacheDir = getCacheDirectory()
        let filename = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return cacheDir.appendingPathComponent("\(filename).txt")
    }

    private func loadLyricsFromDisk(cacheKey: String) -> String? {
        let fileURL = getCacheFileURL(for: cacheKey)

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let lyrics = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        return lyrics
    }

    private func saveLyricsToDisk(lyrics: String, cacheKey: String) {
        let fileURL = getCacheFileURL(for: cacheKey)

        do {
            try lyrics.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            #if DEBUG
            print("Failed to save lyrics to disk: \(error)")
            #endif
        }
    }

    // MARK: - Helper Methods

    private func callCompletion<T>(_ completion: @escaping (Result<T, LyricsError>) -> Void, with result: Result<T, LyricsError>) {
        DispatchQueue.main.async {
            completion(result)
        }
    }
}

// MARK: - Supporting Types

enum LyricsError: Error, LocalizedError {
    case invalidQuery
    case invalidURL
    case networkError(Error)
    case noData
    case parsingError
    case noResults

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
            return "No lyrics found"
        }
    }
}
