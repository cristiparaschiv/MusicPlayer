import SwiftUI
import SFBAudioEngine

struct TrackEditorView: View {
    let track: Track
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var albumArtist: String = ""
    @State private var album: String = ""
    @State private var trackNumber: String = ""
    @State private var discNumber: String = ""
    @State private var year: String = ""
    @State private var genre: String = ""
    @State private var composer: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Track Info")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fieldRow("Title", text: $title)
                    fieldRow("Artist", text: $artist)
                    fieldRow("Album Artist", text: $albumArtist)
                    fieldRow("Album", text: $album)

                    HStack(spacing: 16) {
                        fieldRow("Track #", text: $trackNumber, width: 80)
                        fieldRow("Disc #", text: $discNumber, width: 80)
                        fieldRow("Year", text: $year, width: 80)
                    }

                    fieldRow("Genre", text: $genre)
                    fieldRow("Composer", text: $composer)

                    // File info (read-only)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("File")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(track.filePath)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
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
                Spacer()
                Button("Save") {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 520)
        .onAppear { loadTrackData() }
    }

    private func fieldRow(_ label: String, text: Binding<String>, width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: width ?? .infinity)
        }
    }

    private func loadTrackData() {
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

    private func saveChanges() {
        isSaving = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Write metadata to file using SFBAudioEngine
                let url = URL(fileURLWithPath: track.filePath)
                let audioFile = try AudioFile(readingPropertiesAndMetadataFrom: url)

                audioFile.metadata.title = title.isEmpty ? nil : title
                audioFile.metadata.artist = artist.isEmpty ? nil : artist
                audioFile.metadata.albumArtist = albumArtist.isEmpty ? nil : albumArtist
                audioFile.metadata.albumTitle = album.isEmpty ? nil : album
                audioFile.metadata.trackNumber = Int(trackNumber)
                audioFile.metadata.discNumber = Int(discNumber)
                audioFile.metadata.releaseDate = year.isEmpty ? nil : year
                audioFile.metadata.genre = genre.isEmpty ? nil : genre
                audioFile.metadata.composer = composer.isEmpty ? nil : composer

                try audioFile.writeMetadata()

                // Re-extract metadata and update database
                if let metadata = MediaScannerManager.shared.reExtractMetadata(from: url) {
                    let dao = TrackDAO()
                    dao.updateTrack(metadata: metadata, filePath: track.filePath)
                }

                // Clean up orphaned artists/albums/genres
                MediaScannerManager.shared.updateLibraryStatistics()

                DispatchQueue.main.async {
                    isSaving = false
                    // Notify views to refresh
                    NotificationCenter.default.post(name: Constants.Notifications.trackMetadataChanged, object: nil, userInfo: ["trackId": track.id])
                    NotificationCenter.default.post(name: Constants.Notifications.libraryDidUpdate, object: nil)

                    // Refresh currently playing track if needed
                    if NowPlayingManager.shared.currentTrack?.id == track.id {
                        NowPlayingManager.shared.reloadCurrentTrack()
                    }

                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    isSaving = false
                    let desc = error.localizedDescription
                    if desc.contains("read only") || desc.contains("read-only") || desc.contains("could not be saved") {
                        errorMessage = "File is read-only. Go to Settings and click \"Update Folder Access\" to enable editing."
                    } else {
                        errorMessage = "Failed to save: \(desc)"
                    }
                }
            }
        }
    }
}
