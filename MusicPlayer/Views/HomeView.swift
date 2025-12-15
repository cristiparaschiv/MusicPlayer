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

                // Example Sections
                SectionHeader("New Albums")
                AlbumGrid(albums: recentAlbums)

                SectionHeader("Recently Played")
                AlbumGrid(albums: recentlyPlayedAlbums)

                SectionHeader("Frequently Played")
                AlbumGrid(albums: mostPlayedAlbums)
            }
            .padding()
        }
        .onAppear {
            loadData()
        }
    }

    func loadData() {
        recentAlbums = albumDAO.getRecentlyAdded(limit: 5)

        // Get recently played tracks and convert to albums
        let recentlyPlayedTracks = playHistoryDAO.getRecentlyPlayed(limit: 20)
        recentlyPlayedAlbums = getUniqueAlbums(from: recentlyPlayedTracks, limit: 5)

        // Get most played tracks and convert to albums
        let mostPlayedTracks = playHistoryDAO.getMostPlayed(limit: 20)
        mostPlayedAlbums = getUniqueAlbums(from: mostPlayedTracks, limit: 5)
    }

    func getUniqueAlbums(from tracks: [Track], limit: Int) -> [Album] {
        var uniqueAlbumIds = Set<Int64>()
        var albums: [Album] = []

        for track in tracks {
            if let albumId = track.albumId, !uniqueAlbumIds.contains(albumId) {
                if let album = albumDAO.getById(id: albumId) {
                    albums.append(album)
                    uniqueAlbumIds.insert(albumId)
                    if albums.count >= limit {
                        break
                    }
                }
            }
        }

        return albums
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
