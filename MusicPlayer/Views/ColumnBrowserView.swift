import SwiftUI

struct ColumnBrowserView: View {
    @State private var genres: [String] = []
    @State private var artists: [String] = []
    @State private var albums: [String] = []
    @State private var tracks: [Track] = []

    @State private var selectedGenre: String? = nil
    @State private var selectedArtist: String? = nil
    @State private var selectedAlbum: String? = nil

    @State private var tracksToEdit: [Track]?

    private let trackDAO = TrackDAO()
    private let db = DatabaseManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Column Browser")
                    .font(.largeTitle)
                    .bold()
                Spacer()
                Text("\(tracks.count) tracks")
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            // Column browser
            HStack(spacing: 0) {
                columnView(title: "Genre", items: genres, selection: $selectedGenre)
                Divider()
                columnView(title: "Artist", items: artists, selection: $selectedArtist)
                Divider()
                columnView(title: "Album", items: albums, selection: $selectedAlbum)
            }
            .frame(height: 180)

            Divider()

            // Track list
            TrackTableView(
                tracks: tracks,
                config: TrackTableConfig(onEditTrack: { tracksToEdit = $0 }),
                onPlayTrack: { track, allTracks in
                    if let index = allTracks.firstIndex(where: { $0.id == track.id }) {
                        QueueManager.shared.setQueue(allTracks, startIndex: index)
                        PlayerManager.shared.play(track: track)
                    }
                }
            )
        }
        .onAppear { loadGenres(); loadArtists(); loadAlbums(); loadTracks() }
        .onChange(of: selectedGenre) { _, _ in
            selectedArtist = nil
            selectedAlbum = nil
            loadArtists()
            loadAlbums()
            loadTracks()
        }
        .onChange(of: selectedArtist) { _, _ in
            selectedAlbum = nil
            loadAlbums()
            loadTracks()
        }
        .onChange(of: selectedAlbum) { _, _ in
            loadTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
            loadGenres(); loadArtists(); loadAlbums(); loadTracks()
        }
        .sheet(isPresented: Binding(get: { tracksToEdit != nil }, set: { if !$0 { tracksToEdit = nil } })) {
            if let tracks = tracksToEdit {
                TrackEditorView(tracks: tracks)
            }
        }
    }

    private func columnView(title: String, items: [String], selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)

            List(selection: selection) {
                Text("All (\(items.count))")
                    .tag(nil as String?)
                    .font(.subheadline)

                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.subheadline)
                        .lineLimit(1)
                        .tag(item as String?)
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 150)
    }

    // MARK: - Data Loading

    private func loadGenres() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let sql = "SELECT DISTINCT genre_name FROM tracks WHERE genre_name IS NOT NULL ORDER BY genre_name"
            let results = db.query(sql: sql)
            let loaded = results.compactMap { $0["genre_name"] as? String }
            DispatchQueue.main.async { genres = loaded }
        }
    }

    private func loadArtists() {
        let genre = selectedGenre
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var sql = "SELECT DISTINCT artist_name FROM tracks WHERE artist_name IS NOT NULL"
            var params: [Any] = []
            if let genre = genre {
                sql += " AND genre_name = ?"
                params.append(genre)
            }
            sql += " ORDER BY artist_name"
            let results = db.query(sql: sql, parameters: params)
            let loaded = results.compactMap { $0["artist_name"] as? String }
            DispatchQueue.main.async { artists = loaded }
        }
    }

    private func loadAlbums() {
        let genre = selectedGenre
        let artist = selectedArtist
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var sql = "SELECT DISTINCT album_title FROM tracks WHERE album_title IS NOT NULL"
            var params: [Any] = []
            if let genre = genre {
                sql += " AND genre_name = ?"
                params.append(genre)
            }
            if let artist = artist {
                sql += " AND artist_name = ?"
                params.append(artist)
            }
            sql += " ORDER BY album_title"
            let results = db.query(sql: sql, parameters: params)
            let loaded = results.compactMap { $0["album_title"] as? String }
            DispatchQueue.main.async { albums = loaded }
        }
    }

    private func loadTracks() {
        let genre = selectedGenre
        let artist = selectedArtist
        let album = selectedAlbum
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var sql = "SELECT * FROM tracks WHERE 1=1"
            var params: [Any] = []
            if let genre = genre {
                sql += " AND genre_name = ?"
                params.append(genre)
            }
            if let artist = artist {
                sql += " AND artist_name = ?"
                params.append(artist)
            }
            if let album = album {
                sql += " AND album_title = ?"
                params.append(album)
            }
            sql += " ORDER BY title_sort"
            let results = db.query(sql: sql, parameters: params)
            let loaded = results.compactMap { trackDAO.trackFromRow($0) }
            DispatchQueue.main.async { tracks = loaded }
        }
    }
}
