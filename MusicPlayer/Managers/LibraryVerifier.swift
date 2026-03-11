import Foundation
import Combine
import SFBAudioEngine

struct VerificationResult: Identifiable {
    let id = UUID()
    let trackId: Int64
    let filePath: String
    let trackTitle: String
    let errorType: VerificationError
}

enum VerificationError: String {
    case fileNotFound = "File not found"
    case cannotOpen = "Cannot open file"
    case zeroDuration = "Invalid duration (0)"
    case tooSmall = "File too small"
}

class LibraryVerifier: ObservableObject {
    @Published var isVerifying: Bool = false
    @Published var progress: Double = 0
    @Published var results: [VerificationResult] = []
    @Published var totalChecked: Int = 0

    private let trackDAO = TrackDAO()

    func verify() {
        isVerifying = true
        progress = 0
        results = []
        totalChecked = 0

        let dao = trackDAO
        Task.detached { [weak self] in
            let allTracks = dao.getAll()
            let total = allTracks.count
            var issues: [VerificationResult] = []

            for (index, track) in allTracks.enumerated() {
                let url = URL(fileURLWithPath: track.filePath)

                if !FileManager.default.fileExists(atPath: track.filePath) {
                    issues.append(VerificationResult(trackId: track.id, filePath: track.filePath, trackTitle: track.title, errorType: .fileNotFound))
                } else if let attrs = try? FileManager.default.attributesOfItem(atPath: track.filePath),
                          let size = attrs[.size] as? Int64, size < 128 {
                    issues.append(VerificationResult(trackId: track.id, filePath: track.filePath, trackTitle: track.title, errorType: .tooSmall))
                } else {
                    do {
                        let audioFile = try AudioFile(readingPropertiesAndMetadataFrom: url)
                        if let duration = audioFile.properties.duration, duration <= 0 {
                            issues.append(VerificationResult(trackId: track.id, filePath: track.filePath, trackTitle: track.title, errorType: .zeroDuration))
                        }
                    } catch {
                        issues.append(VerificationResult(trackId: track.id, filePath: track.filePath, trackTitle: track.title, errorType: .cannotOpen))
                    }
                }

                if index % 10 == 0 || index == total - 1 {
                    let currentIssues = issues
                    let currentIndex = index
                    await MainActor.run {
                        self?.progress = Double(currentIndex + 1) / Double(total)
                        self?.totalChecked = currentIndex + 1
                        self?.results = currentIssues
                    }
                }
            }

            await MainActor.run {
                self?.isVerifying = false
                self?.progress = 1.0
                self?.results = issues
            }
        }
    }

    func removeTrack(id: Int64) {
        trackDAO.delete(trackId: id)
        results.removeAll { $0.trackId == id }
        NotificationCenter.default.post(name: Constants.Notifications.libraryDidUpdate, object: nil)
    }

    func removeAllDamaged() {
        for result in results {
            trackDAO.delete(trackId: result.trackId)
        }
        results.removeAll()
        NotificationCenter.default.post(name: Constants.Notifications.libraryDidUpdate, object: nil)
    }
}
