import Foundation

class LyricsManager {
    static let shared = LyricsManager()

    // MARK: - Properties

    private let lyricsQueue = DispatchQueue(label: "com.orangemusicplayer.lyrics", qos: .utility)
    private var memoryCache: [String: String] = [:]
    private let cacheLock = NSLock()
    private let trackDAO = TrackDAO()

    private let geniusBaseURL = "https://genius.com"
    private let geniusAPIBaseURL = "https://genius.com/api"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Fetch lyrics for a track
    func fetchLyrics(for track: Track, completion: @escaping (Result<String, LyricsError>) -> Void) {
        fetchLyrics(title: track.title, artist: track.artistName ?? track.albumArtistName, completion: completion)
    }

    /// Fetch lyrics by title and artist
    func fetchLyrics(title: String, artist: String?, completion: @escaping (Result<String, LyricsError>) -> Void) {
        lyricsQueue.async { [weak self] in
            guard let self = self else { return }

            // Generate cache key
            let cacheKey = self.generateCacheKey(title: title, artist: artist)

            // Check memory cache
            if let cachedLyrics = self.getCachedLyrics(for: cacheKey) {
                print("Lyrics found in memory cache for: \(title)")
                self.callCompletion(completion, with: .success(cachedLyrics))
                return
            }

            // Check disk cache
            if let diskCachedLyrics = self.loadLyricsFromDisk(cacheKey: cacheKey) {
                print("Lyrics found in disk cache for: \(title)")
                self.cacheLyrics(diskCachedLyrics, for: cacheKey)
                self.callCompletion(completion, with: .success(diskCachedLyrics))
                return
            }

            // Fetch from Genius
            print("Fetching lyrics from Genius for: \(title) by \(artist ?? "Unknown")")
            self.fetchFromGenius(title: title, artist: artist) { result in
                switch result {
                case .success(let lyrics):
                    // Cache the lyrics
                    self.cacheLyrics(lyrics, for: cacheKey)
                    self.saveLyricsToDisk(lyrics: lyrics, cacheKey: cacheKey)
                    self.callCompletion(completion, with: .success(lyrics))

                case .failure(let error):
                    self.callCompletion(completion, with: .failure(error))
                }
            }
        }
    }

    /// Fetch and save lyrics for current track
    func fetchAndSaveLyrics(for track: Track, completion: ((Result<String, LyricsError>) -> Void)? = nil) {
        fetchLyrics(for: track) { [weak self] result in
            guard let self = self else { return }

            if case .success(let lyrics) = result {
                // Save to database
                self.lyricsQueue.async {
                    self.saveLyricsToDatabase(trackId: track.id, lyrics: lyrics)
                }
            }

            if let completion = completion {
                self.callCompletion(completion, with: result)
            }
        }
    }

    /// Clear memory cache
    func clearMemoryCache() {
        cacheLock.lock()
        memoryCache.removeAll()
        cacheLock.unlock()
        print("Lyrics memory cache cleared")
    }

    /// Clear disk cache
    func clearDiskCache() {
        let cacheDir = getCacheDirectory()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        print("Lyrics disk cache cleared")
    }

    /// Clear all caches
    func clearAllCaches() {
        clearMemoryCache()
        clearDiskCache()
    }

    // MARK: - Private Methods - Genius API

    private func fetchFromGenius(title: String, artist: String?, completion: @escaping (Result<String, LyricsError>) -> Void) {
        // Step 1: Search for the song
        searchGenius(title: title, artist: artist) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let songURL):
                // Step 2: Scrape lyrics from the URL
                self.scrapeLyrics(from: songURL, completion: completion)

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func searchGenius(title: String, artist: String?, completion: @escaping (Result<URL, LyricsError>) -> Void) {
        // Build search query
        var searchQuery = title
        if let artist = artist {
            searchQuery = "\(artist) \(title)"
        }

        guard let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(.failure(.invalidQuery))
            return
        }

        // Construct search URL
        guard let searchURL = URL(string: "\(geniusAPIBaseURL)/search/multi?q=\(encodedQuery)") else {
            completion(.failure(.invalidURL))
            return
        }

        print("Searching Genius: \(searchURL.absoluteString)")

        // Create request with User-Agent header (required to avoid being blocked)
        var request = URLRequest(url: searchURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Perform search request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in

            if let error = error {
                print("Genius search error: \(error)")
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
                   let response = json["response"] as? [String: Any],
                   let sections = response["sections"] as? [[String: Any]] {

                    // Find the first song result
                    for section in sections {
                        if let type = section["type"] as? String,
                           type == "song" || type == "top_hit",
                           let hits = section["hits"] as? [[String: Any]] {

                            for hit in hits {
                                if let result = hit["result"] as? [String: Any],
                                   let urlString = result["url"] as? String,
                                   let url = URL(string: urlString) {

                                    print("Found song: \(urlString)")
                                    completion(.success(url))
                                    return
                                }
                            }
                        }
                    }
                }

                // No results found
                completion(.failure(.noResults))

            } catch {
                print("JSON parsing error: \(error)")
                completion(.failure(.parsingError))
            }
        }

        task.resume()
    }

    // MARK: - Private Methods - Web Scraping

    private func scrapeLyrics(from url: URL, completion: @escaping (Result<String, LyricsError>) -> Void) {
        print("Scraping lyrics from: \(url.absoluteString)")

        // Create request with User-Agent header (required to avoid being blocked)
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Scraping error: \(error)")
                completion(.failure(.networkError(error)))
                return
            }

            guard let data = data,
                  let html = String(data: data, encoding: .utf8) else {
                completion(.failure(.noData))
                return
            }

            // Extract lyrics from HTML
            if let lyrics = self.extractLyricsFromHTML(html) {
                print("Successfully extracted lyrics")
                completion(.success(lyrics))
            } else {
                print("Failed to extract lyrics from HTML")
                completion(.failure(.parsingError))
            }
        }

        task.resume()
    }

    private func extractLyricsFromHTML(_ html: String) -> String? {
        // Genius stores lyrics in multiple div elements with data-lyrics-container="true"
        var lyrics = ""

        // Find all lyrics container divs
        let lyricsPattern = #"<div[^>]*data-lyrics-container="true"[^>]*>(.*?)</div>"#

        guard let regex = try? NSRegularExpression(pattern: lyricsPattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        for match in matches {
            if match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: html) {
                let content = String(html[range])
                let cleanedContent = cleanHTML(content)
                lyrics += cleanedContent + "\n\n"
            }
        }

        // Clean up the final lyrics
        lyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)

        return lyrics.isEmpty ? nil : lyrics
    }

    private func cleanHTML(_ html: String) -> String {
        var cleaned = html

        // Replace line breaks
        cleaned = cleaned.replacingOccurrences(of: "<br/>", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "<br>", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "<br />", with: "\n")

        // Remove all HTML tags
        cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode HTML entities
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
        cleaned = cleaned.replacingOccurrences(of: "&lt;", with: "<")
        cleaned = cleaned.replacingOccurrences(of: "&gt;", with: ">")
        cleaned = cleaned.replacingOccurrences(of: "&quot;", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "&#39;", with: "'")
        cleaned = cleaned.replacingOccurrences(of: "&apos;", with: "'")
        cleaned = cleaned.replacingOccurrences(of: "&#x27;", with: "'")
        cleaned = cleaned.replacingOccurrences(of: "&nbsp;", with: " ")

        // Clean up whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove excessive blank lines
        while cleaned.contains("\n\n\n") {
            cleaned = cleaned.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return cleaned
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text

        // Common HTML entities
        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&#x27;": "'",
            "&nbsp;": " "
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        return result
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
            print("Saved lyrics to disk: \(fileURL.lastPathComponent)")
        } catch {
            print("Failed to save lyrics to disk: \(error)")
        }
    }

    private func saveLyricsToDatabase(trackId: Int64, lyrics: String) {
        // TODO: Add updateLyrics method to TrackDAO
        // For now, we'll just log
        print("TODO: Save lyrics to database for track \(trackId)")

        // Post notification that lyrics were loaded
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Constants.Notifications.lyricsDidLoad,
                object: nil,
                userInfo: ["trackId": trackId, "lyrics": lyrics]
            )
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
    case scrapingFailed

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
        case .scrapingFailed:
            return "Failed to scrape lyrics"
        }
    }
}
