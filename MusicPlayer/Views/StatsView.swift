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
    @State private var period: StatsPeriod = .year
    @State private var totalTracks: Int = 0
    @State private var totalListeningTime: TimeInterval = 0
    @State private var tracksPlayed: Int = 0
    @State private var topArtists: [ArtistStats] = []
    @State private var topAlbums: [AlbumStats] = []
    @State private var topGenres: [GenreStats] = []
    @State private var dailyActivity: [DailyPlayCount] = []
    @State private var isLoading = false

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

                // Activity Heatmap — always render, graceful when empty
                activityHeatmap

                // Top sections
                HStack(alignment: .top, spacing: 20) {
                    topArtistsSection
                    topGenresSection
                }

                topAlbumsSection
            }
            .padding()
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
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

    // MARK: - Activity Heatmap (GitHub-style 365-day grid)

    private var activityHeatmap: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Daily Activity")
                    .font(.headline)
                Spacer()
                if dailyActivity.isEmpty {
                    Text("No plays yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    heatmapLegend
                }
            }

            ActivityHeatmapGrid(
                dailyActivity: dailyActivity,
                endDate: Date()
            )
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var heatmapLegend: some View {
        HStack(spacing: 4) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(ActivityHeatmapGrid.color(forLevel: level))
                    .frame(width: 10, height: 10)
            }
            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
            } else if topGenres.count < 2 {
                // Not enough variance to make a donut meaningful — list only.
                EmptyView()
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

    // MARK: - Heatmap grid view

    private func loadStats() {
        isLoading = true
        let since = period.startDate
        let dao = statsDAO
        Task.detached {
            let tracks = dao.getTotalTracks()
            let listening = dao.getTotalListeningTime(since: since)
            let played = dao.getTracksPlayedCount(since: since)
            let artists = dao.getTopArtists(since: since)
            let albums = dao.getTopAlbums(since: since)
            let genres = dao.getTopGenres(since: since)
            let activitySince = since ?? Calendar.current.date(byAdding: .year, value: -1, to: Date())!
            let activity = dao.getDailyPlayCounts(since: activitySince)
            await MainActor.run {
                totalTracks = tracks
                totalListeningTime = listening
                tracksPlayed = played
                topArtists = artists
                topAlbums = albums
                topGenres = genres
                dailyActivity = activity
                isLoading = false
            }
        }
    }
}

// MARK: - Activity Heatmap Grid

/// GitHub-style calendar heatmap covering the 52 weeks ending at `endDate`.
struct ActivityHeatmapGrid: View {
    let dailyActivity: [DailyPlayCount]
    let endDate: Date

    private let weeks = 53
    private let cellSize: CGFloat = 11
    private let cellSpacing: CGFloat = 3

    /// Map of startOfDay → play count, for O(1) lookup.
    private var countsByDay: [Date: Int] {
        var map: [Date: Int] = [:]
        let calendar = Calendar.current
        for entry in dailyActivity {
            map[calendar.startOfDay(for: entry.date)] = entry.count
        }
        return map
    }

    /// Max count in the window — used to bucket intensities.
    private var maxCount: Int {
        max(dailyActivity.map(\.count).max() ?? 0, 1)
    }

    var body: some View {
        let counts = countsByDay
        let calendar = Calendar.current
        // Align to the start of the week containing endDate so columns are weeks.
        let endStart = calendar.startOfDay(for: endDate)
        let weekday = calendar.component(.weekday, from: endStart) - 1 // 0=Sun
        let lastColumnStart = calendar.date(byAdding: .day, value: -weekday, to: endStart) ?? endStart
        let firstColumnStart = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: lastColumnStart) ?? endStart

        return HStack(alignment: .top, spacing: cellSpacing) {
            // Day-of-week labels (Mon/Wed/Fri)
            VStack(alignment: .trailing, spacing: cellSpacing) {
                ForEach(0..<7, id: \.self) { day in
                    Text(dayLabel(day))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(height: cellSize)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(0..<weeks, id: \.self) { weekIndex in
                        VStack(spacing: cellSpacing) {
                            ForEach(0..<7, id: \.self) { dayIndex in
                                let day = calendar.date(
                                    byAdding: .day,
                                    value: weekIndex * 7 + dayIndex,
                                    to: firstColumnStart
                                ) ?? firstColumnStart
                                cell(for: day, count: counts[day] ?? 0, inRange: day <= endStart)
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func cell(for day: Date, count: Int, inRange: Bool) -> some View {
        let level = inRange ? Self.level(count: count, max: maxCount) : -1
        return RoundedRectangle(cornerRadius: 2)
            .fill(level < 0 ? Color.clear : Self.color(forLevel: level))
            .frame(width: cellSize, height: cellSize)
            .help(inRange ? "\(count) \(count == 1 ? "play" : "plays") · \(Self.dateFormatter.string(from: day))" : "")
    }

    private func dayLabel(_ day: Int) -> String {
        switch day {
        case 1: return "Mon"
        case 3: return "Wed"
        case 5: return "Fri"
        default: return ""
        }
    }

    /// Bucket a count into 0..4 based on the window's max.
    static func level(count: Int, max: Int) -> Int {
        guard count > 0 else { return 0 }
        let ratio = Double(count) / Double(max)
        switch ratio {
        case ..<0.25: return 1
        case ..<0.5: return 2
        case ..<0.75: return 3
        default: return 4
        }
    }

    static func color(forLevel level: Int) -> Color {
        switch level {
        case 1: return Color.accentColor.opacity(0.25)
        case 2: return Color.accentColor.opacity(0.5)
        case 3: return Color.accentColor.opacity(0.75)
        case 4: return Color.accentColor
        default: return Color.secondary.opacity(0.12)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
}
