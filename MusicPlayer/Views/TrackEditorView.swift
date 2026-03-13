import SwiftUI
import SFBAudioEngine

struct TrackEditorView: View {
    let tracks: [Track]
    @Environment(\.dismiss) var dismiss

    // Field values
    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var albumArtist: String = ""
    @State private var album: String = ""
    @State private var trackNumber: String = ""
    @State private var discNumber: String = ""
    @State private var year: String = ""
    @State private var genre: String = ""
    @State private var composer: String = ""

    // Dirty tracking — only save fields the user actually changed
    @State private var dirtyFields: Set<TagField> = []

    // Placeholders for batch mode
    @State private var placeholders: [TagField: String] = [:]

    @State private var isSaving: Bool = false
    @State private var saveProgress: Double = 0
    @State private var errorMessage: String?

    // Auto-identify
    @State private var isIdentifying = false
    @State private var identifyResults: [IdentifyResult] = []
    @State private var showIdentifyResults = false
    @State private var identifyError: String?

    private var isBatchMode: Bool { tracks.count > 1 }

    enum TagField: String, CaseIterable {
        case title, artist, albumArtist, album, trackNumber, discNumber, year, genre, composer
    }

    // Single track convenience init
    init(track: Track) {
        self.tracks = [track]
    }

    init(tracks: [Track]) {
        self.tracks = tracks
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isBatchMode ? "Edit \(tracks.count) Tracks" : "Edit Track Info")
                        .font(.headline)
                    if isBatchMode {
                        Text("Only modified fields will be saved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Form (scrollable)
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title — only in single-track mode
                if !isBatchMode {
                    HStack(spacing: 8) {
                        fieldRow(.title, label: "Title", text: $title)
                        if !isIdentifying {
                            Button(action: identifyTrack) {
                                Label("Identify", systemImage: "waveform.and.magnifyingglass")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Identify track using audio fingerprint")
                            .padding(.top, 16)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.top, 16)
                        }
                    }
                }

                if let error = identifyError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if showIdentifyResults && !identifyResults.isEmpty {
                    identifyResultsPicker
                }

                fieldRow(.artist, label: "Artist", text: $artist)
                fieldRow(.albumArtist, label: "Album Artist", text: $albumArtist)
                fieldRow(.album, label: "Album", text: $album)

                HStack(spacing: 16) {
                    fieldRow(.trackNumber, label: "Track #", text: $trackNumber, width: 80)
                    fieldRow(.discNumber, label: "Disc #", text: $discNumber, width: 80)
                    fieldRow(.year, label: "Year", text: $year, width: 80)

                    if isBatchMode {
                        Button(action: autoNumberTracks) {
                            Label("Auto-number", systemImage: "number")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Detect track numbers from filenames")
                        .padding(.top, 16)
                    }
                }

                fieldRow(.genre, label: "Genre", text: $genre)
                fieldRow(.composer, label: "Composer", text: $composer)

                // File info (read-only)
                VStack(alignment: .leading, spacing: 4) {
                    Text("File")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isBatchMode {
                        Text("\(tracks.count) files selected")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(tracks.first?.filePath ?? "")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding()
            }

            Divider()

            // Footer
            HStack {
                if isSaving && isBatchMode {
                    ProgressView(value: saveProgress)
                        .frame(width: 120)
                    Text("\(Int(saveProgress * Double(tracks.count)))/\(tracks.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save") {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || (isBatchMode && dirtyFields.isEmpty))
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 480, height: isBatchMode ? 520 : 600)
        .onAppear { loadTrackData() }
    }

    // MARK: - Identify Results Picker

    private var identifyResultsPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Matches found — click to apply:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(identifyResults) { result in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(result.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(result.artist)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    if !result.album.isEmpty {
                                        Text("—")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                        Text(result.album)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .lineLimit(1)
                                HStack(spacing: 6) {
                                    if !result.year.isEmpty {
                                        Text(result.year)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                    }
                                    if let tn = result.trackNumber {
                                        Text("Track \(tn)")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                    }
                                    if let dn = result.discNumber, dn > 1 {
                                        Text("Disc \(dn)")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Spacer()
                            Text("\(Int(result.confidence * 100))%")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(result.confidence > 0.9 ? .green : result.confidence > 0.7 ? .orange : .red)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.05))
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            applyIdentifyResult(result)
                        }
                        .onHover { hovering in
                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(identifyResults.count) * 52, 200))
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - Field Row

    private func fieldRow(_ field: TagField, label: String, text: Binding<String>, width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isBatchMode && dirtyFields.contains(field) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                }
            }
            TextField(
                placeholders[field] ?? label,
                text: Binding(
                    get: { text.wrappedValue },
                    set: { newValue in
                        text.wrappedValue = newValue
                        dirtyFields.insert(field)
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: width ?? .infinity)
        }
    }

    // MARK: - Data Loading

    private func loadTrackData() {
        if isBatchMode {
            loadBatchData()
        } else if let track = tracks.first {
            loadSingleTrackData(track)
        }
    }

    private func loadSingleTrackData(_ track: Track) {
        title = track.title
        artist = track.artistName ?? ""
        albumArtist = track.albumArtistName ?? ""
        album = track.albumTitle ?? ""
        trackNumber = track.trackNumber.map { "\($0)" } ?? ""
        discNumber = track.discNumber.map { "\($0)" } ?? ""
        year = track.year.map { "\($0)" } ?? ""
        genre = track.genreName ?? ""
        composer = track.composerName ?? ""
    }

    private func loadBatchData() {
        // For each field, check if all tracks share the same value
        let artists = Set(tracks.compactMap(\.artistName))
        let albumArtists = Set(tracks.compactMap(\.albumArtistName))
        let albums = Set(tracks.compactMap(\.albumTitle))
        let trackNumbers = Set(tracks.compactMap(\.trackNumber))
        let discNumbers = Set(tracks.compactMap(\.discNumber))
        let years = Set(tracks.compactMap(\.year))
        let genres = Set(tracks.compactMap(\.genreName))
        let composers = Set(tracks.compactMap(\.composerName))

        func setField(_ value: String?, placeholder: String, field: TagField, target: inout String) {
            if let value = value {
                target = value
            } else {
                placeholders[field] = placeholder
            }
        }

        setField(artists.count == 1 ? artists.first : nil, placeholder: "Multiple Values", field: .artist, target: &artist)
        setField(albumArtists.count == 1 ? albumArtists.first : nil, placeholder: "Multiple Values", field: .albumArtist, target: &albumArtist)
        setField(albums.count == 1 ? albums.first : nil, placeholder: "Multiple Values", field: .album, target: &album)
        setField(genres.count == 1 ? genres.first : nil, placeholder: "Multiple Values", field: .genre, target: &genre)
        setField(composers.count == 1 ? composers.first : nil, placeholder: "Multiple Values", field: .composer, target: &composer)
        setField(years.count == 1 ? years.first.map { "\($0)" } : nil, placeholder: "Multiple Values", field: .year, target: &year)
        setField(discNumbers.count == 1 ? discNumbers.first.map { "\($0)" } : nil, placeholder: "Multiple Values", field: .discNumber, target: &discNumber)

        // Track numbers are almost always different, so always show placeholder
        if trackNumbers.count == 1 {
            trackNumber = trackNumbers.first.map { "\($0)" } ?? ""
        } else {
            placeholders[.trackNumber] = "Multiple Values"
        }
    }

    // MARK: - Auto-Number

    private func autoNumberTracks() {
        // Try to extract track numbers from filenames
        var detectedNumbers: [(index: Int, number: Int)] = []

        for (i, track) in tracks.enumerated() {
            let filename = URL(fileURLWithPath: track.filePath).deletingPathExtension().lastPathComponent

            // Try patterns: "01 - Song", "01. Song", "01_Song", "01 Song", "(01) Song"
            let patterns = [
                "^(\\d{1,3})\\s*[-._)\\s]",  // Leading digits followed by separator
                "^\\(?\\s*(\\d{1,3})\\s*\\)?\\s*[-._\\s]",  // Digits possibly in parens
            ]

            var found = false
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
                   match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: filename),
                   let num = Int(filename[range]) {
                    detectedNumbers.append((i, num))
                    found = true
                    break
                }
            }

            if !found {
                // Could not detect for this file
                detectedNumbers.append((i, 0))
            }
        }

        let validNumbers = detectedNumbers.filter { $0.number > 0 }
        if validNumbers.count == tracks.count {
            // All detected — apply. But since batch mode writes same value to all,
            // auto-number doesn't fit batch field model. Show message instead.
            errorMessage = "Track numbers detected from filenames. They will be applied individually on save."
            // Store in a side channel for save
            autoDetectedTrackNumbers = Dictionary(uniqueKeysWithValues: detectedNumbers.map { (tracks[$0.index].id, $0.number) })
            dirtyFields.insert(.trackNumber)
            trackNumber = "Auto"
        } else if validNumbers.isEmpty {
            errorMessage = "Could not detect track numbers from filenames. Set them manually."
        } else {
            errorMessage = "Could only detect \(validNumbers.count)/\(tracks.count) track numbers. Set missing ones manually."
            autoDetectedTrackNumbers = Dictionary(uniqueKeysWithValues: validNumbers.map { (tracks[$0.index].id, $0.number) })
            dirtyFields.insert(.trackNumber)
            trackNumber = "Auto (partial)"
        }
    }

    @State private var autoDetectedTrackNumbers: [Int64: Int] = [:]

    // MARK: - Identify Track (Single Mode)

    private func identifyTrack() {
        guard let track = tracks.first, !isBatchMode else { return }
        isIdentifying = true
        identifyError = nil
        showIdentifyResults = false
        identifyResults = []

        AudioFingerprintService.shared.identify(track: track) { results in
            DispatchQueue.main.async {
                isIdentifying = false
                if let results = results, !results.isEmpty {
                    identifyResults = results
                    showIdentifyResults = true
                    // If single high-confidence match, auto-select it
                    if results.count == 1 && results[0].confidence > 0.9 {
                        applyIdentifyResult(results[0])
                    }
                } else {
                    identifyError = "Could not identify this track. Try searching manually."
                }
            }
        }
    }

    private func applyIdentifyResult(_ result: IdentifyResult) {
        title = result.title
        artist = result.artist
        album = result.album
        if !result.albumArtist.isEmpty { albumArtist = result.albumArtist }
        if let num = result.trackNumber { trackNumber = "\(num)" }
        if let num = result.discNumber { discNumber = "\(num)" }
        if !result.year.isEmpty { year = result.year }
        if !result.genre.isEmpty { genre = result.genre }
        showIdentifyResults = false
        // Mark all populated fields as dirty
        dirtyFields = Set(TagField.allCases)
    }

    // MARK: - Save

    private func saveChanges() {
        let fieldsToSave = isBatchMode ? dirtyFields : Set(TagField.allCases)

        // Capture field values for background work
        let titleVal = title
        let artistVal = artist
        let albumArtistVal = albumArtist
        let albumVal = album
        let trackNumberVal = trackNumber
        let discNumberVal = discNumber
        let yearVal = year
        let genreVal = genre
        let composerVal = composer
        let autoNumbers = autoDetectedTrackNumbers
        let batchMode = isBatchMode
        let tracksCopy = tracks

        // Step 1: Collect old IDs before updating, then update DB (instant)
        let dao = TrackDAO()
        var oldArtistIds = Set<Int64>()
        var oldAlbumIds = Set<Int64>()
        var oldGenreIds = Set<Int64>()
        var oldComposerIds = Set<Int64>()

        for track in tracksCopy {
            if let id = track.artistId { oldArtistIds.insert(id) }
            if let id = track.albumId { oldAlbumIds.insert(id) }
            if let id = track.genreId { oldGenreIds.insert(id) }
            if let id = track.composerId { oldComposerIds.insert(id) }
        }

        for track in tracksCopy {
            dao.updateTrackTags(
                trackId: track.id,
                title: fieldsToSave.contains(.title) && !batchMode ? (titleVal.isEmpty ? nil : titleVal) : nil,
                artist: fieldsToSave.contains(.artist) ? (artistVal.isEmpty ? nil : artistVal) : nil,
                albumArtist: fieldsToSave.contains(.albumArtist) ? (albumArtistVal.isEmpty ? nil : albumArtistVal) : nil,
                album: fieldsToSave.contains(.album) ? (albumVal.isEmpty ? nil : albumVal) : nil,
                trackNumber: fieldsToSave.contains(.trackNumber) ? (autoNumbers[track.id] ?? Int(trackNumberVal)) : nil,
                discNumber: fieldsToSave.contains(.discNumber) ? Int(discNumberVal) : nil,
                year: fieldsToSave.contains(.year) ? Int(yearVal) : nil,
                genre: fieldsToSave.contains(.genre) ? (genreVal.isEmpty ? nil : genreVal) : nil,
                composer: fieldsToSave.contains(.composer) ? (composerVal.isEmpty ? nil : composerVal) : nil
            )
        }

        // Clean up orphaned records from old IDs
        dao.cleanupOrphanedRecords(artistIds: oldArtistIds, albumIds: oldAlbumIds, genreIds: oldGenreIds, composerIds: oldComposerIds)

        // Step 2: Dismiss and notify immediately
        dismiss()

        let changedIds = tracksCopy.map { $0.id }
        NotificationCenter.default.post(
            name: Constants.Notifications.trackMetadataChanged,
            object: nil,
            userInfo: ["trackIds": changedIds]
        )

        if let currentId = NowPlayingManager.shared.currentTrack?.id,
           tracksCopy.contains(where: { $0.id == currentId }) {
            NowPlayingManager.shared.reloadCurrentTrack()
        }

        // Step 3: Write file metadata in background (slow for NAS files)
        DispatchQueue.global(qos: .utility).async {
            for track in tracksCopy {
                do {
                    let url = URL(fileURLWithPath: track.filePath)
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                    let audioFile = try AudioFile(readingPropertiesAndMetadataFrom: url)

                    if fieldsToSave.contains(.title) && !batchMode {
                        audioFile.metadata.title = titleVal.isEmpty ? nil : titleVal
                    }
                    if fieldsToSave.contains(.artist) {
                        audioFile.metadata.artist = artistVal.isEmpty ? nil : artistVal
                    }
                    if fieldsToSave.contains(.albumArtist) {
                        audioFile.metadata.albumArtist = albumArtistVal.isEmpty ? nil : albumArtistVal
                    }
                    if fieldsToSave.contains(.album) {
                        audioFile.metadata.albumTitle = albumVal.isEmpty ? nil : albumVal
                    }
                    if fieldsToSave.contains(.trackNumber) {
                        if let autoNum = autoNumbers[track.id] {
                            audioFile.metadata.trackNumber = autoNum
                        } else if trackNumberVal != "Auto" && trackNumberVal != "Auto (partial)" {
                            audioFile.metadata.trackNumber = Int(trackNumberVal)
                        }
                    }
                    if fieldsToSave.contains(.discNumber) {
                        audioFile.metadata.discNumber = Int(discNumberVal)
                    }
                    if fieldsToSave.contains(.year) {
                        audioFile.metadata.releaseDate = yearVal.isEmpty ? nil : yearVal
                    }
                    if fieldsToSave.contains(.genre) {
                        audioFile.metadata.genre = genreVal.isEmpty ? nil : genreVal
                    }
                    if fieldsToSave.contains(.composer) {
                        audioFile.metadata.composer = composerVal.isEmpty ? nil : composerVal
                    }

                    try audioFile.writeMetadata()
                } catch {
                    let trackTitle = track.title
                    let errorDesc = error.localizedDescription
                    DispatchQueue.main.async {
                        self.errorMessage = "File write failed for \"\(trackTitle)\": \(errorDesc). Database was updated successfully."
                    }
                }
            }

            // Skip updateLibraryStatistics — too expensive for tag edits.
            // Orphaned records will be cleaned up on next library scan.
        }
    }
}