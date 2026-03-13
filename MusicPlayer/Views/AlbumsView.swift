import SwiftUI

struct AlbumsView: View {
    @State private var allAlbums: [Album] = []
    @State private var sortOrder: AlbumSortOrder = .title
    @State private var scrollTarget: String?
    private let albumDAO = AlbumDAO()

    private var sortedAlbums: [Album] {
        switch sortOrder {
        case .title:
            return allAlbums.sorted { $0.titleSort.localizedCaseInsensitiveCompare($1.titleSort) == .orderedAscending }
        case .artist:
            return allAlbums.sorted {
                ($0.artistName ?? "").localizedCaseInsensitiveCompare($1.artistName ?? "") == .orderedAscending
            }
        case .year:
            return allAlbums.sorted { ($1.year ?? 0) < ($0.year ?? 0) }
        case .recentlyAdded:
            return allAlbums.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    private var showSectionIndex: Bool {
        sortOrder == .title || sortOrder == .artist
    }

    private var groupedAlbums: [(letter: String, albums: [Album])] {
        let grouped = Dictionary(grouping: sortedAlbums) { album -> String in
            let key: String
            switch sortOrder {
            case .title:
                key = String(album.titleSort.prefix(1)).uppercased()
            case .artist:
                key = String((album.artistName ?? "Unknown").sortKey.prefix(1)).uppercased()
            default:
                return ""
            }
            if key.first?.isLetter == true { return key }
            return "#"
        }
        return grouped.sorted { $0.key < $1.key }
            .map { (letter: $0.key, albums: $0.value) }
    }

    private var availableLetters: Set<String> {
        Set(groupedAlbums.map { $0.letter })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Albums")
                    .font(.largeTitle)
                    .bold()

                Spacer()

                Picker("Sort", selection: $sortOrder) {
                    ForEach(AlbumSortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
            }
            .padding()

            ZStack(alignment: .trailing) {
                if allAlbums.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "square.stack")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("No Albums Yet")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Text("Add a music folder in Settings to get started")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        if showSectionIndex {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)], spacing: 20) {
                                ForEach(groupedAlbums, id: \.letter) { group in
                                    Section {
                                        ForEach(group.albums) { album in
                                            AlbumGridItem(album: album)
                                        }
                                    } header: {
                                        Text(group.letter)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.top, group.letter == groupedAlbums.first?.letter ? 0 : 12)
                                            .id(group.letter)
                                    }
                                }
                            }
                            .padding()
                            .padding(.trailing, 20)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)], spacing: 20) {
                                ForEach(sortedAlbums) { album in
                                    AlbumGridItem(album: album)
                                }
                            }
                            .padding()
                        }
                    }
                    .onChange(of: scrollTarget) { letter in
                        if let letter {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(letter, anchor: .top)
                            }
                            scrollTarget = nil
                        }
                    }
                }

                if showSectionIndex {
                    SectionIndexView(
                        availableLetters: availableLetters,
                        onSelect: { letter in
                            scrollTarget = letter
                        }
                    )
                }
            }
        }
        .onAppear { loadAlbums() }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
            loadAlbums()
        }
    }

    private func loadAlbums() {
        allAlbums = albumDAO.getAll()
    }
}

// MARK: - Album Sort Order

enum AlbumSortOrder: String, CaseIterable, Identifiable {
    case title = "title"
    case artist = "artist"
    case year = "year"
    case recentlyAdded = "recentlyAdded"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: return "Title (A-Z)"
        case .artist: return "Artist (A-Z)"
        case .year: return "Year (Newest)"
        case .recentlyAdded: return "Recently Added"
        }
    }
}
