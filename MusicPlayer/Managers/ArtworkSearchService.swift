import Foundation
import AppKit

/// Represents a single artwork option from any source
struct ArtworkOption: Identifiable, Equatable {
    let id = UUID()
    let source: ArtworkSource
    let thumbnailURL: URL?
    let fullURL: URL?
    let localImage: NSImage? // For local file results
    let label: String // e.g. "Front", "Back", "Disc"
    let dimensions: String? // e.g. "1000x1000"

    static func == (lhs: ArtworkOption, rhs: ArtworkOption) -> Bool {
        lhs.id == rhs.id
    }
}

enum ArtworkSource: String {
    case coverArtArchive = "Cover Art Archive"
    case iTunes = "iTunes"
    case localFolder = "Local"
    case userFile = "File"
}

/// Searches multiple sources for album artwork
class ArtworkSearchService {
    private let musicBrainzBaseURL = "https://musicbrainz.org/ws/2"
    private let coverArtArchiveURL = "https://coverartarchive.org"
    private var lastMusicBrainzRequest: Date?
    private let rateLimitInterval: TimeInterval = 1.0

    /// Search all sources for artwork matching the album/artist query
    func search(album: String, artist: String?, completion: @escaping ([ArtworkOption], _ networkError: Bool) -> Void) {
        var allResults: [ArtworkOption] = []
        var hadNetworkError = false
        let group = DispatchGroup()
        let lock = NSLock()

        func append(_ results: [ArtworkOption]) {
            lock.lock()
            allResults.append(contentsOf: results)
            lock.unlock()
        }

        func markNetworkError() {
            lock.lock()
            hadNetworkError = true
            lock.unlock()
        }

        // 1. Local folder artwork
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let results = self.searchLocalFolder(album: album, artist: artist)
            append(results)
            group.leave()
        }

        // 2. Cover Art Archive (via MusicBrainz)
        group.enter()
        searchCoverArtArchive(album: album, artist: artist) { results, error in
            append(results)
            if error { markNetworkError() }
            group.leave()
        }

        // 3. iTunes Search API
        group.enter()
        searchITunes(album: album, artist: artist) { results, error in
            append(results)
            if error { markNetworkError() }
            group.leave()
        }

        group.notify(queue: .main) {
            completion(allResults, hadNetworkError)
        }
    }

    // MARK: - Local Folder Search

    private func searchLocalFolder(album: String, artist: String?) -> [ArtworkOption] {
        let trackDAO = TrackDAO()
        let albumDAO = AlbumDAO()

        let albums = albumDAO.search(query: album)
        guard let matchedAlbum = albums.first(where: { $0.artistName == artist || artist == nil }) else {
            return []
        }

        let tracks = trackDAO.getByAlbumId(albumId: matchedAlbum.id)
        guard let firstTrack = tracks.first else { return [] }

        let directory = URL(fileURLWithPath: firstTrack.filePath).deletingLastPathComponent()
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return []
        }

        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "bmp", "tiff"])
        var results: [ArtworkOption] = []

        for fileURL in contents {
            let ext = fileURL.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }

            if let image = NSImage(contentsOf: fileURL) {
                let size = image.size
                results.append(ArtworkOption(
                    source: .localFolder,
                    thumbnailURL: fileURL,
                    fullURL: fileURL,
                    localImage: image,
                    label: fileURL.lastPathComponent,
                    dimensions: "\(Int(size.width))x\(Int(size.height))"
                ))
            }
        }

        return results
    }

    // MARK: - Cover Art Archive

    private func searchCoverArtArchive(album: String, artist: String?, completion: @escaping ([ArtworkOption], _ networkError: Bool) -> Void) {
        // First find the release on MusicBrainz
        searchMusicBrainzRelease(album: album, artist: artist) { [weak self] releaseId in
            guard let self = self, let releaseId = releaseId else {
                completion([], false)
                return
            }

            // Then get ALL images from Cover Art Archive (not just front)
            guard let listURL = URL(string: "\(self.coverArtArchiveURL)/release/\(releaseId)") else {
                completion([], false)
                return
            }

            URLSession.shared.dataTask(with: listURL) { data, _, error in
                let hadError = error != nil
                if let error = error {
                    #if DEBUG
                    print("[ArtworkSearch] Cover Art Archive error: \(error.localizedDescription)")
                    #endif
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let images = json["images"] as? [[String: Any]] else {
                    completion([], hadError)
                    return
                }

                var results: [ArtworkOption] = []
                for imageInfo in images {
                    guard let imageURL = imageInfo["image"] as? String,
                          let fullURL = URL(string: imageURL) else { continue }

                    let types = imageInfo["types"] as? [String] ?? []
                    let label = types.first ?? "Unknown"

                    // Use thumbnails dict for preview
                    let thumbnails = imageInfo["thumbnails"] as? [String: Any]
                    let thumbURLStr = (thumbnails?["small"] as? String) ?? (thumbnails?["250"] as? String)
                    let thumbURL = thumbURLStr.flatMap { URL(string: $0) }

                    results.append(ArtworkOption(
                        source: .coverArtArchive,
                        thumbnailURL: thumbURL ?? fullURL,
                        fullURL: fullURL,
                        localImage: nil,
                        label: label,
                        dimensions: nil
                    ))
                }

                completion(results, false)
            }.resume()
        }
    }

    private func searchMusicBrainzRelease(album: String, artist: String?, completion: @escaping (String?) -> Void) {
        var query = "release:\"\(album)\""
        if let artist = artist {
            query += " AND artist:\"\(artist)\""
        }

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "\(musicBrainzBaseURL)/release/?query=\(encodedQuery)&fmt=json") else {
            completion(nil)
            return
        }

        // Rate limit
        let delay: TimeInterval
        if let last = lastMusicBrainzRequest {
            delay = max(0, rateLimitInterval - Date().timeIntervalSince(last))
        } else {
            delay = 0
        }
        lastMusicBrainzRequest = Date().addingTimeInterval(delay)

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
            var request = URLRequest(url: searchURL)
            request.setValue(
                "\(Constants.musicBrainzAppName)/\(Constants.musicBrainzVersion) ( \(Constants.musicBrainzContact) )",
                forHTTPHeaderField: "User-Agent"
            )

            URLSession.shared.dataTask(with: request) { data, _, error in
                if let error = error {
                    #if DEBUG
                    print("[ArtworkSearch] MusicBrainz error: \(error.localizedDescription)")
                    #endif
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let releases = json["releases"] as? [[String: Any]],
                      let first = releases.first,
                      let releaseId = first["id"] as? String else {
                    completion(nil)
                    return
                }
                completion(releaseId)
            }.resume()
        }
    }

    // MARK: - iTunes Search API

    private func searchITunes(album: String, artist: String?, completion: @escaping ([ArtworkOption], _ networkError: Bool) -> Void) {
        var searchTerm = album
        if let artist = artist {
            searchTerm = "\(artist) \(album)"
        }

        guard let encoded = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=album&limit=10") else {
            completion([], false)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            let hadError = error != nil
            if let error = error {
                #if DEBUG
                print("[ArtworkSearch] iTunes error: \(error.localizedDescription)")
                #endif
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                completion([], hadError)
                return
            }

            var options: [ArtworkOption] = []
            for result in results {
                guard let artworkURL100 = result["artworkUrl100"] as? String else { continue }

                let collectionName = result["collectionName"] as? String ?? "Unknown"
                let artistName = result["artistName"] as? String ?? ""

                // Replace 100x100 with higher resolutions
                let thumbURL = URL(string: artworkURL100.replacingOccurrences(of: "100x100", with: "300x300"))
                let fullURL = URL(string: artworkURL100.replacingOccurrences(of: "100x100", with: "1000x1000"))

                options.append(ArtworkOption(
                    source: .iTunes,
                    thumbnailURL: thumbURL,
                    fullURL: fullURL,
                    localImage: nil,
                    label: "\(collectionName) — \(artistName)",
                    dimensions: "1000x1000"
                ))
            }

            completion(options, false)
        }.resume()
    }
}
