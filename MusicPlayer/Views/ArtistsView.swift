import SwiftUI

struct ArtistsView: View {
    @State private var allArtists: [Artist] = []
    @State private var sortOrder: ArtistSortOrder = .name
    private let artistDAO = ArtistDAO()

    private var sortedArtists: [Artist] {
        switch sortOrder {
        case .name:
            return allArtists.sorted { $0.nameSort.localizedCaseInsensitiveCompare($1.nameSort) == .orderedAscending }
        case .nameDesc:
            return allArtists.sorted { $0.nameSort.localizedCaseInsensitiveCompare($1.nameSort) == .orderedDescending }
        case .mostAlbums:
            return allArtists.sorted { $0.albumCount > $1.albumCount }
        }
    }

    private var groupedArtists: [(letter: String, artists: [Artist])] {
        let grouped = Dictionary(grouping: sortedArtists) { artist -> String in
            let key = artist.nameSort.prefix(1).uppercased()
            if key.first?.isLetter == true {
                return key
            }
            return "#"
        }
        return grouped.sorted { $0.key < $1.key }
            .map { (letter: $0.key, artists: $0.value) }
    }

    private var availableLetters: Set<String> {
        Set(groupedArtists.map { $0.letter })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Artists")
                    .font(.largeTitle)
                    .bold()

                Spacer()

                Picker("Sort", selection: $sortOrder) {
                    ForEach(ArtistSortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            .padding()

            ZStack(alignment: .trailing) {
                if allArtists.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "person.2")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("No Artists Yet")
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
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)], spacing: 20) {
                            ForEach(groupedArtists, id: \.letter) { group in
                                Section {
                                    ForEach(group.artists) { artist in
                                        ArtistGridItem(artist: artist)
                                    }
                                } header: {
                                    Text(group.letter)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, group.letter == groupedArtists.first?.letter ? 0 : 12)
                                        .id(group.letter)
                                }
                            }
                        }
                        .padding()
                        .padding(.trailing, 20)
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

                // A-Z index strip
                SectionIndexView(
                    availableLetters: availableLetters,
                    onSelect: { letter in
                        scrollTarget = letter
                    }
                )
            }
        }
        .onAppear { loadArtists() }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
            loadArtists()
        }
    }

    @State private var scrollTarget: String?

    private func loadArtists() {
        allArtists = artistDAO.getAll()
    }
}

// MARK: - Artist Sort Order

enum ArtistSortOrder: String, CaseIterable, Identifiable {
    case name = "name"
    case nameDesc = "nameDesc"
    case mostAlbums = "mostAlbums"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Name (A-Z)"
        case .nameDesc: return "Name (Z-A)"
        case .mostAlbums: return "Most Albums"
        }
    }
}
