import SwiftUI
import UniformTypeIdentifiers

struct ArtworkPickerView: View {
    let album: Album
    let onDismiss: () -> Void

    @State private var searchText: String = ""
    @State private var results: [ArtworkOption] = []
    @State private var isSearching = false
    @State private var selectedOption: ArtworkOption?
    @State private var isSaving = false
    @State private var currentArtwork: NSImage?
    @State private var isDragTargeted = false
    @State private var networkError = false

    private let searchService = ArtworkSearchService()
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            // Header with current artwork and album info
            headerSection
                .padding()

            Divider()

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search artwork...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        performSearch()
                    }
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button("Search") {
                    performSearch()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Results grid
            if isSearching {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else if results.isEmpty && !searchText.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: networkError ? "wifi.slash" : "photo.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(networkError ? "Network error" : "No artwork found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(networkError ? "Check your internet connection and try again" : "Try adjusting the search terms")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else if results.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "arrow.up.doc")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Search for artwork or drag an image here")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(results) { option in
                            ArtworkOptionCell(
                                option: option,
                                isSelected: selectedOption?.id == option.id
                            )
                            .onTapGesture {
                                selectedOption = option
                            }
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Bottom action bar
            HStack {
                if let selected = selectedOption {
                    HStack(spacing: 4) {
                        Text("Selected:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selected.source.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                        if let dims = selected.dimensions {
                            Text("(\(dims))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(action: applyArtwork) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 60)
                    } else {
                        Text("Apply")
                            .frame(width: 60)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedOption == nil || isSaving)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
        .onDrop(of: [.image, .fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .overlay {
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.1))
                    .padding(4)
            }
        }
        .onAppear {
            // Pre-fill search with album info and auto-search
            var query = album.title
            if let artist = album.artistName {
                query = "\(artist) \(album.title)"
            }
            searchText = query
            loadCurrentArtwork()
            performSearch()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 16) {
            // Current artwork
            Group {
                if let artwork = currentArtwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.secondary.opacity(0.2)
                        Image(systemName: Icons.opticalDiscFill)
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 64, height: 64)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.headline)
                    .lineLimit(1)
                if let artist = album.artistName {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Paste from clipboard button
            Button(action: pasteFromClipboard) {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .help("Paste image from clipboard (Cmd+V)")
        }
    }

    // MARK: - Actions

    private func loadCurrentArtwork() {
        ArtworkManager.shared.fetchAlbumArtwork(for: album) { result in
            if case .success(let image) = result {
                currentArtwork = image
            }
        }
    }

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        selectedOption = nil

        let searchAlbum = album.title
        let searchArtist = album.artistName

        // Use the full text for external search but album info for local
        searchService.search(album: searchAlbum, artist: searchArtist) { results, hadNetworkError in
            // Also search with the custom query if different
            if searchText != "\(searchArtist ?? "") \(searchAlbum)".trimmingCharacters(in: .whitespaces) {
                // Re-search with custom terms for online sources
                let customSearch = ArtworkSearchService()
                customSearch.search(album: searchText, artist: nil) { customResults, customNetworkError in
                    // Merge, avoiding duplicates by source+label
                    var merged = results
                    let existingKeys = Set(results.map { "\($0.source.rawValue)-\($0.label)" })
                    for r in customResults where !existingKeys.contains("\(r.source.rawValue)-\(r.label)") {
                        merged.append(r)
                    }
                    self.results = merged
                    self.networkError = hadNetworkError || customNetworkError
                    self.isSearching = false
                }
            } else {
                self.results = results
                self.networkError = hadNetworkError
                self.isSearching = false
            }
        }
    }

    private func applyArtwork() {
        guard let option = selectedOption else { return }
        isSaving = true

        DispatchQueue.global(qos: .userInitiated).async {
            let image: NSImage?

            if let localImage = option.localImage {
                image = localImage
            } else if let fullURL = option.fullURL {
                // Download full resolution image
                if fullURL.isFileURL {
                    image = NSImage(contentsOf: fullURL)
                } else if let data = try? Data(contentsOf: fullURL) {
                    image = NSImage(data: data)
                } else {
                    image = nil
                }
            } else {
                image = nil
            }

            DispatchQueue.main.async {
                if let image = image {
                    ArtworkManager.shared.saveArtwork(for: album, image: image)
                    currentArtwork = ArtworkManager.shared.resizeImage(image, to: 300) ?? image
                }
                isSaving = false
                if image != nil {
                    onDismiss()
                }
            }
        }
    }

    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard) else { return }

        let option = ArtworkOption(
            source: .userFile,
            thumbnailURL: nil,
            fullURL: nil,
            localImage: image,
            label: "Pasted Image",
            dimensions: "\(Int(image.size.width))x\(Int(image.size.height))"
        )
        results.insert(option, at: 0)
        selectedOption = option
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            // Try loading as image
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { item, _ in
                    guard let image = item as? NSImage else { return }
                    DispatchQueue.main.async {
                        let option = ArtworkOption(
                            source: .userFile,
                            thumbnailURL: nil,
                            fullURL: nil,
                            localImage: image,
                            label: "Dropped Image",
                            dimensions: "\(Int(image.size.width))x\(Int(image.size.height))"
                        )
                        results.insert(option, at: 0)
                        selectedOption = option
                    }
                }
                return
            }

            // Try loading as file URL
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      let image = NSImage(contentsOf: url) else { return }
                DispatchQueue.main.async {
                    let option = ArtworkOption(
                        source: .userFile,
                        thumbnailURL: url,
                        fullURL: url,
                        localImage: image,
                        label: url.lastPathComponent,
                        dimensions: "\(Int(image.size.width))x\(Int(image.size.height))"
                    )
                    results.insert(option, at: 0)
                    selectedOption = option
                }
            }
        }
    }
}

// MARK: - Artwork Option Cell

struct ArtworkOptionCell: View {
    let option: ArtworkOption
    let isSelected: Bool

    @State private var thumbnail: NSImage?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 6) {
            // Thumbnail
            ZStack {
                Color.secondary.opacity(0.1)
                    .aspectRatio(1, contentMode: .fit)

                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .clear, radius: 4)

            // Source badge and label
            HStack(spacing: 4) {
                Text(option.source.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(badgeColor.opacity(0.15))
                    .foregroundColor(badgeColor)
                    .cornerRadius(3)

                Text(option.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private var badgeColor: Color {
        switch option.source {
        case .coverArtArchive: return .blue
        case .iTunes: return .pink
        case .localFolder: return .green
        case .userFile: return .orange
        }
    }

    private func loadThumbnail() {
        if let localImage = option.localImage {
            thumbnail = localImage
            isLoading = false
            return
        }

        guard let url = option.thumbnailURL else {
            isLoading = false
            return
        }

        if url.isFileURL {
            thumbnail = NSImage(contentsOf: url)
            isLoading = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data, let image = NSImage(data: data) {
                    thumbnail = image
                }
                isLoading = false
            }
        }.resume()
    }
}
