import Foundation
import Combine

class ExternalTrackManager: ObservableObject {
    static let shared = ExternalTrackManager()

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var trackCount: Int = 0

    private let dao = ExternalTrackDAO()
    private let scanner = MediaScannerManager.shared
    private let importQueue = DispatchQueue(label: "com.orangemusicplayer.externaltrack", qos: .userInitiated)

    private init() {
        reload()
    }

    // MARK: - Import

    func importURLs(_ urls: [URL]) {
        importQueue.async { [weak self] in
            guard let self = self else { return }

            var importedTracks: [Track] = []
            let fileManager = FileManager.default
            let supportedExtensions = self.scanner.supportedExtensions

            for url in urls {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

                if isDirectory.boolValue {
                    // Recursively enumerate audio files
                    if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
                        while let fileURL = enumerator.nextObject() as? URL {
                            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                                if let track = self.importFile(fileURL) {
                                    importedTracks.append(track)
                                }
                            }
                        }
                    }
                } else {
                    if supportedExtensions.contains(url.pathExtension.lowercased()) {
                        if let track = self.importFile(url) {
                            importedTracks.append(track)
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                self.reload()

                if !importedTracks.isEmpty && PlayerManager.shared.playbackState == .stopped {
                    QueueManager.shared.setQueue(importedTracks)
                    PlayerManager.shared.play()
                }
            }
        }
    }

    private func importFile(_ url: URL) -> Track? {
        guard let metadata = scanner.extractMetadata(from: url) else { return nil }
        guard let trackId = dao.insert(metadata: metadata) else { return nil }

        // Build a Track from the metadata for queue usage
        return Track(
            id: trackId,
            title: metadata.title ?? "Unknown",
            titleSort: (metadata.title ?? "Unknown").sortKey,
            artistId: nil,
            artistName: metadata.artist,
            albumId: nil,
            albumTitle: metadata.album,
            albumArtistName: metadata.albumArtist,
            trackNumber: metadata.trackNumber,
            discNumber: metadata.discNumber,
            year: metadata.year,
            genreId: nil,
            genreName: metadata.genre,
            composerId: nil,
            composerName: metadata.composer,
            duration: metadata.duration,
            bitrate: metadata.bitrate,
            sampleRate: metadata.sampleRate,
            channelCount: metadata.channelCount,
            formatName: metadata.formatName,
            bitDepth: metadata.bitDepth,
            filePath: metadata.filePath,
            fileSize: metadata.fileSize,
            dateAdded: Date(),
            dateModified: Date(),
            lastPlayed: nil,
            playCount: 0,
            rating: nil,
            isFavorite: false,
            hasArtwork: false,
            lyrics: metadata.lyrics,
            replayGainTrackGain: metadata.replayGainTrackGain,
            replayGainAlbumGain: metadata.replayGainAlbumGain,
            startTime: nil,
            endTime: nil
        )
    }

    // MARK: - Management

    func clearAll() {
        dao.clearAll()
        reload()
    }

    func removeTrack(id: Int64) {
        dao.removeTrack(id: id)
        reload()
    }

    func reload() {
        let loadedTracks = dao.getAllTracks()
        let count = loadedTracks.count
        let update = {
            self.tracks = loadedTracks
            self.trackCount = count
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }
}
