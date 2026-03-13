import Foundation
import AVFoundation

/// Audio fingerprinting service using Chromaprint C library + AcoustID for track identification.
/// Uses AVFoundation for audio decoding and the linked libchromaprint.a for fingerprint generation.
class AudioFingerprintService {
    static let shared = AudioFingerprintService()

    private let acoustIDAPIKey = "d7GRFGIE1s"
    private let session = URLSession.shared
    private let sampleRate: Int32 = 44100
    private let channels: Int32 = 1 // mono is fine for fingerprinting
    private let maxDuration: TimeInterval = 120 // only fingerprint first 120s

    private init() {}

    /// Identify a track by its audio fingerprint.
    func identify(track: Track, completion: @escaping ([IdentifyResult]?) -> Void) {
        generateFingerprint(filePath: track.filePath) { [weak self] fingerprint, duration in
            guard let self = self, let fingerprint = fingerprint, let duration = duration else {
                completion(nil)
                return
            }

            self.queryAcoustID(fingerprint: fingerprint, duration: duration) { recordings in
                guard let recordings = recordings, !recordings.isEmpty else {
                    completion(nil)
                    return
                }

                let results = self.parseRecordings(recordings)
                completion(results.isEmpty ? nil : results)
            }
        }
    }

    // MARK: - Fingerprint Generation (Chromaprint C API + AVFoundation)

    private func generateFingerprint(filePath: String, completion: @escaping (String?, Int?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let fileURL = URL(fileURLWithPath: filePath)
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

            // Decode audio to PCM using AVFoundation
            guard let (pcmData, totalDuration) = self.decodeAudioToPCM(url: fileURL) else {
                #if DEBUG
                print("[AudioFingerprint] Failed to decode audio")
                #endif
                completion(nil, nil)
                return
            }

            let sampleCount = pcmData.count / MemoryLayout<Int16>.size
            let duration = Int(totalDuration) // Use real file duration, not decoded length

            // Generate fingerprint using Chromaprint
            guard let ctx = chromaprint_new(Int32(CHROMAPRINT_ALGORITHM_DEFAULT.rawValue)) else {
                #if DEBUG
                print("[AudioFingerprint] Failed to create chromaprint context")
                #endif
                completion(nil, nil)
                return
            }
            defer { chromaprint_free(ctx) }

            guard chromaprint_start(ctx, self.sampleRate, self.channels) == 1 else {
                #if DEBUG
                print("[AudioFingerprint] chromaprint_start failed")
                #endif
                completion(nil, nil)
                return
            }

            let feedResult = pcmData.withUnsafeBytes { rawBuffer -> Int32 in
                guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: Int16.self) else { return 0 }
                return chromaprint_feed(ctx, ptr, Int32(sampleCount))
            }

            guard feedResult == 1 else {
                #if DEBUG
                print("[AudioFingerprint] chromaprint_feed failed")
                #endif
                completion(nil, nil)
                return
            }

            guard chromaprint_finish(ctx) == 1 else {
                #if DEBUG
                print("[AudioFingerprint] chromaprint_finish failed")
                #endif
                completion(nil, nil)
                return
            }

            var fingerprintPtr: UnsafeMutablePointer<CChar>?
            guard chromaprint_get_fingerprint(ctx, &fingerprintPtr) == 1,
                  let fp = fingerprintPtr else {
                #if DEBUG
                print("[AudioFingerprint] Failed to get fingerprint")
                #endif
                completion(nil, nil)
                return
            }

            let fingerprint = String(cString: fp)
            chromaprint_dealloc(fp)

            #if DEBUG
            print("[AudioFingerprint] Fingerprint length: \(fingerprint.count), duration: \(duration)s")
            #endif
            completion(fingerprint, duration)
        }
    }

    /// Decode audio file to 16-bit signed PCM at 44100 Hz mono. Returns (pcmData, totalDurationInSeconds).
    private func decodeAudioToPCM(url: URL) -> (Data, TimeInterval)? {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            #if DEBUG
            print("[AudioFingerprint] Cannot open audio file: \(url.lastPathComponent)")
            #endif
            return nil
        }
        let totalDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: true
        ) else {
            #if DEBUG
            print("[AudioFingerprint] Cannot create output format")
            #endif
            return nil
        }

        let inputFormat = audioFile.processingFormat
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let maxFrames = AVAudioFrameCount(Double(sampleRate) * maxDuration)
        let framesToRead = min(totalFrames, maxFrames)

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: framesToRead) else {
            #if DEBUG
            print("[AudioFingerprint] Cannot create input buffer")
            #endif
            return nil
        }

        do {
            try audioFile.read(into: inputBuffer, frameCount: framesToRead)
        } catch {
            #if DEBUG
            print("[AudioFingerprint] Cannot read audio: \(error)")
            #endif
            return nil
        }

        // Convert to target format
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            #if DEBUG
            print("[AudioFingerprint] Cannot create converter")
            #endif
            return nil
        }

        let outputFrameCapacity = AVAudioFrameCount(
            Double(framesToRead) * Double(sampleRate) / inputFormat.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
            #if DEBUG
            print("[AudioFingerprint] Cannot create output buffer")
            #endif
            return nil
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if status == .error {
            #if DEBUG
            print("[AudioFingerprint] Conversion error: \(error?.localizedDescription ?? "unknown")")
            #endif
            return nil
        }

        // Extract raw Int16 bytes
        guard let int16Ptr = outputBuffer.int16ChannelData else {
            #if DEBUG
            print("[AudioFingerprint] No int16 channel data")
            #endif
            return nil
        }

        let byteCount = Int(outputBuffer.frameLength) * Int(channels) * MemoryLayout<Int16>.size
        return (Data(bytes: int16Ptr[0], count: byteCount), totalDuration)
    }

    // MARK: - AcoustID Query

    private func queryAcoustID(fingerprint: String, duration: Int, completion: @escaping ([[String: Any]]?) -> Void) {
        // AcoustID requires POST for long fingerprints
        var request = URLRequest(url: URL(string: "https://api.acoustid.org/v2/lookup")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Build form body manually — fingerprint is already base64url-safe from chromaprint
        let body = "client=\(acoustIDAPIKey)&duration=\(duration)&meta=recordings+releasegroups+releases+tracks+compress&fingerprint=\(fingerprint)"
        request.httpBody = body.data(using: .utf8)

        #if DEBUG
        print("[AudioFingerprint] Querying AcoustID (duration: \(duration)s)")
        #endif
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                #if DEBUG
                print("[AudioFingerprint] AcoustID network error: \(error)")
                #endif
                completion(nil)
                return
            }
            guard let data = data else {
                #if DEBUG
                print("[AudioFingerprint] AcoustID no data")
                #endif
                completion(nil)
                return
            }
            #if DEBUG
            print("[AudioFingerprint] AcoustID response length: \(data.count) bytes")
            #endif
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String, status == "ok",
                  let results = json["results"] as? [[String: Any]] else {
                #if DEBUG
                print("[AudioFingerprint] AcoustID parse failed")
                #endif
                completion(nil)
                return
            }

            var allRecordings: [[String: Any]] = []
            for result in results {
                let score = result["score"] as? Double ?? 0
                if let recordings = result["recordings"] as? [[String: Any]] {
                    for var recording in recordings {
                        recording["score"] = score * 100
                        allRecordings.append(recording)
                    }
                }
            }

            completion(allRecordings.isEmpty ? nil : allRecordings)
        }.resume()
    }

    // MARK: - Parse Results

    private func parseRecordings(_ recordings: [[String: Any]]) -> [IdentifyResult] {
        var results: [IdentifyResult] = []

        for recording in recordings {
            guard let title = recording["title"] as? String else { continue }

            let artists = recording["artists"] as? [[String: Any]]
            let artistName = artists?.first?["name"] as? String ?? "Unknown Artist"

            let scoreDouble = recording["score"] as? Double
            let scoreInt = (recording["score"] as? Int).map { Double($0) }
            let score = (scoreDouble ?? scoreInt ?? 0) / 100.0

            let releaseGroups = recording["releasegroups"] as? [[String: Any]] ?? []

            if releaseGroups.isEmpty {
                // Recording with no release groups
                results.append(IdentifyResult(
                    title: title, artist: artistName, album: "",
                    albumArtist: "", trackNumber: nil, discNumber: nil,
                    year: "", genre: "", confidence: score
                ))
                continue
            }

            // Create one result per release group so user can pick the right album
            for rg in releaseGroups {
                let albumTitle = rg["title"] as? String ?? ""
                let albumArtists = rg["artists"] as? [[String: Any]]
                let albumArtistName = albumArtists?.first?["name"] as? String ?? ""
                let rgType = rg["type"] as? String ?? ""
                let secondaryTypes = rg["secondarytypes"] as? [String] ?? []

                // Look through releases for year, track/disc number
                let releases = rg["releases"] as? [[String: Any]] ?? []
                var year = ""
                var trackNumber: Int?
                var discNumber: Int?

                for release in releases {
                    // Year — prefer earliest
                    if let dateDict = release["date"] as? [String: Any],
                       let y = dateDict["year"] as? Int {
                        if year.isEmpty || "\(y)" < year {
                            year = "\(y)"
                        }
                    }

                    // Track/disc number from mediums
                    if trackNumber == nil, let mediums = release["mediums"] as? [[String: Any]] {
                        for medium in mediums {
                            let disc = medium["position"] as? Int
                            if let tracks = medium["tracks"] as? [[String: Any]] {
                                for t in tracks {
                                    // Match by recording title
                                    if disc != nil { discNumber = disc }
                                    if let pos = t["position"] as? Int {
                                        trackNumber = pos
                                        break
                                    }
                                }
                            }
                            if trackNumber != nil { break }
                        }
                    }
                }

                // Slightly penalize compilations so original albums rank higher
                var adjustedScore = score
                if secondaryTypes.contains("Compilation") {
                    adjustedScore *= 0.9
                }

                results.append(IdentifyResult(
                    title: title,
                    artist: artistName,
                    album: albumTitle,
                    albumArtist: albumArtistName,
                    trackNumber: trackNumber,
                    discNumber: discNumber,
                    year: year,
                    genre: "",
                    confidence: adjustedScore
                ))
            }
        }

        // Sort by confidence, deduplicate by title+artist+album
        var seen = Set<String>()
        return results.sorted { $0.confidence > $1.confidence }.filter {
            let key = "\($0.title.lowercased())|\($0.artist.lowercased())|\($0.album.lowercased())"
            return seen.insert(key).inserted
        }.prefix(10).map { $0 }
    }
}
