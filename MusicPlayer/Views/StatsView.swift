import SwiftUI
import Charts

enum StatsPeriod: String, CaseIterable {
    case week = "This Week"
    case month = "This Month"
    case year = "This Year"
    case allTime = "All Time"

    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -7, to: Date())
        case .month: return calendar.date(byAdding: .month, value: -1, to: Date())
        case .year: return calendar.date(byAdding: .year, value: -1, to: Date())
        case .allTime: return nil
        }
    }
}

struct StatsView: View {
    @State private var period: StatsPeriod = .month
    @State private var totalTracks: Int = 0
    @State private var totalListeningTime: TimeInterval = 0
    @State private var tracksPlayed: Int = 0
    @State private var topArtists: [ArtistStats] = []
    @State private var topAlbums: [AlbumStats] = []
    @State private var topGenres: [GenreStats] = []
    @State private var dailyActivity: [DailyPlayCount] = []

    private let statsDAO = StatsDAO()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with period selector
                HStack {
                    Text("Listening Statistics")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    Picker("Period", selection: $period) {
                        ForEach(StatsPeriod.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 350)
                }

                // Overview Cards
                overviewCards

                // Activity Chart
                if !dailyActivity.isEmpty {
                    activityChart
                }

                // Top sections
                HStack(alignment: .top, spacing: 20) {
                    topArtistsSection
                    topGenresSection
                }

                topAlbumsSection
            }
            .padding()
        }
        .onAppear { loadStats() }
        .onChange(of: period) { _, _ in loadStats() }
    }

    // MARK: - Overview Cards

    private var overviewCards: some View {
        HStack(spacing: 16) {
            statCard("Tracks in Library", value: "\(totalTracks)", icon: "music.note")
            statCard("Tracks Played", value: "\(tracksPlayed)", icon: "play.circle")
            statCard("Listening Time", value: formattedListeningTime, icon: "clock")
        }
    }

    private func statCard(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Activity Chart

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Activity")
                .font(.headline)

            Chart(dailyActivity, id: \.date) { entry in
                BarMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Plays", entry.count)
                )
                .foregroundStyle(.orange.gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : (period == .month ? 5 : 30))) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    AxisGridLine()
                }
            }
            .frame(height: 180)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Top Artists

    private var topArtistsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Artists")
                .font(.headline)

            if topArtists.isEmpty {
                emptyStateView(icon: "person.2", message: "Play some music to see your top artists")
            } else {
                ForEach(Array(topArtists.enumerated()), id: \.element.name) { index, artist in
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(artist.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(artist.playCount) plays")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        navigateToArtist(name: artist.name)
                    }
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Top Genres

    private var topGenresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Genres")
                .font(.headline)

            if topGenres.isEmpty {
                emptyStateView(icon: "guitars", message: "Genre stats appear as you listen")
            } else {
                Chart(topGenres.prefix(8), id: \.name) { genre in
                    SectorMark(
                        angle: .value("Plays", genre.playCount),
                        innerRadius: .ratio(0.5)
                    )
                    .foregroundStyle(by: .value("Genre", genre.name))
                }
                .frame(height: 180)

                ForEach(topGenres.prefix(5), id: \.name) { genre in
                    HStack {
                        Text(genre.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text("\(genre.playCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Top Albums

    private var topAlbumsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Albums")
                .font(.headline)

            if topAlbums.isEmpty {
                emptyStateView(icon: "square.stack", message: "Your most played albums will show here")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(topAlbums.prefix(8), id: \.albumId) { album in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(album.artistName ?? "Unknown")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("\(album.playCount) plays")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateToAlbum(id: album.albumId)
                        }
                        .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func emptyStateView(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func navigateToArtist(name: String) {
        let artists = ArtistDAO().search(query: name, limit: 1)
        if let artist = artists.first(where: { $0.name == name }) ?? artists.first {
            NotificationCenter.default.post(name: Constants.Notifications.navigateToArtist, object: artist)
        }
    }

    private func navigateToAlbum(id: Int64) {
        let albumDAO = AlbumDAO()
        if let album = albumDAO.getById(id: id) {
            NotificationCenter.default.post(name: Constants.Notifications.navigateToAlbum, object: album)
        }
    }

    private var formattedListeningTime: String {
        let hours = Int(totalListeningTime) / 3600
        let minutes = (Int(totalListeningTime) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func loadStats() {
        let since = period.startDate
        totalTracks = statsDAO.getTotalTracks()
        totalListeningTime = statsDAO.getTotalListeningTime(since: since)
        tracksPlayed = statsDAO.getTracksPlayedCount(since: since)
        topArtists = statsDAO.getTopArtists(since: since)
        topAlbums = statsDAO.getTopAlbums(since: since)
        topGenres = statsDAO.getTopGenres(since: since)

        let activitySince = since ?? Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        dailyActivity = statsDAO.getDailyPlayCounts(since: activitySince)
    }
}
