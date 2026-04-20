import SwiftUI

struct HomeView: View {

    let albumDAO = AlbumDAO()
    let trackDAO = TrackDAO()
    let playHistoryDAO = PlayHistoryDAO()

    @State private var recentAlbums: [Album] = []
    @State private var recentlyPlayedAlbums: [Album] = []
    @State private var mostPlayedAlbums: [Album] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Shuffle Buttons
                HStack {
                    Button("Shuffle all") {
                        shuffleAll()
                    }
                    .buttonStyle(.bordered)

                    Button("Shuffle favorites") {
                        shuffleFavorites()
                    }
                    .buttonStyle(.bordered)
                }

                // Jump back in — horizontal carousel of recently played
                if !recentlyPlayedAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Jump back in")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(recentlyPlayedAlbums, id: \.id) { album in
                                    AlbumGridItem(album: album)
                                        .frame(width: 170)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.bottom, 2)
                        }
                    }
                }

                // Sections — only show if populated
                if !recentAlbums.isEmpty {
                    SectionHeader("New Albums")
                    AlbumGrid(albums: recentAlbums)
                }

                if !mostPlayedAlbums.isEmpty {
                    SectionHeader("Frequently Played")
                    AlbumGrid(albums: mostPlayedAlbums)
                }

                if recentAlbums.isEmpty && recentlyPlayedAlbums.isEmpty && mostPlayedAlbums.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.house")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Your library is waiting")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Start playing music to see your listening activity here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .padding()
        }
        .onAppear {
            loadData()
        }
    }

    func loadData() {
        DispatchQueue.global(qos: .userInitiated).async {
            let recent = albumDAO.getRecentlyAdded(limit: 5)

            let recentlyPlayedTracks = playHistoryDAO.getRecentlyPlayed(limit: 40)
            let recentlyPlayed = getUniqueAlbums(from: recentlyPlayedTracks, limit: 10)

            let mostPlayedTracks = playHistoryDAO.getMostPlayed(limit: 20)
            let mostPlayed = getUniqueAlbums(from: mostPlayedTracks, limit: 5)

            DispatchQueue.main.async {
                recentAlbums = recent
                recentlyPlayedAlbums = recentlyPlayed
                mostPlayedAlbums = mostPlayed
            }
        }
    }

    func getUniqueAlbums(from tracks: [Track], limit: Int) -> [Album] {
        // Collect unique album IDs in order
        var uniqueAlbumIds: [Int64] = []
        var seen = Set<Int64>()
        for track in tracks {
            if let albumId = track.albumId, !seen.contains(albumId) {
                seen.insert(albumId)
                uniqueAlbumIds.append(albumId)
                if uniqueAlbumIds.count >= limit { break }
            }
        }

        // Batch fetch albums
        return uniqueAlbumIds.compactMap { albumDAO.getById(id: $0) }
    }

    func shuffleAll() {
        // Get all tracks from the library
        let allTracks = trackDAO.getAll()

        guard !allTracks.isEmpty else { return }

        // Shuffle the tracks
        var shuffledTracks = allTracks
        shuffledTracks.shuffle()

        // Set the queue and start playing
        QueueManager.shared.setQueue(shuffledTracks, startIndex: 0)
        QueueManager.shared.setShuffleEnabled(true)

        if let firstTrack = shuffledTracks.first {
            PlayerManager.shared.play(track: firstTrack)
        }
    }

    func shuffleFavorites() {
        // Get all favorite tracks
        let favoriteTracks = trackDAO.getFavorites()

        guard !favoriteTracks.isEmpty else { return }

        // Shuffle the tracks
        var shuffledTracks = favoriteTracks
        shuffledTracks.shuffle()

        // Set the queue and start playing
        QueueManager.shared.setQueue(shuffledTracks, startIndex: 0)
        QueueManager.shared.setShuffleEnabled(true)

        if let firstTrack = shuffledTracks.first {
            PlayerManager.shared.play(track: firstTrack)
        }
    }
}

struct SectionHeader: View {
    var title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.title2)
            .bold()
            .padding(.horizontal, 4)
    }
}
