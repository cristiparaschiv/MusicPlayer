import Foundation

struct Album {
    let id: Int64
    let title: String
    let titleSort: String
    let artistId: Int64?
    let artistName: String?
    let year: Int?
    let genreId: Int64?
    let genreName: String?
    let trackCount: Int
    let totalDuration: TimeInterval
    let dateAdded: Date
    let artworkPath: String?

    init(id: Int64,
         title: String,
         titleSort: String? = nil,
         artistId: Int64? = nil,
         artistName: String? = nil,
         year: Int? = nil,
         genreId: Int64? = nil,
         genreName: String? = nil,
         trackCount: Int = 0,
         totalDuration: TimeInterval = 0,
         dateAdded: Date = Date(),
         artworkPath: String? = nil) {
        self.id = id
        self.title = title
        self.titleSort = titleSort ?? title.sortKey
        self.artistId = artistId
        self.artistName = artistName
        self.year = year
        self.genreId = genreId
        self.genreName = genreName
        self.trackCount = trackCount
        self.totalDuration = totalDuration
        self.dateAdded = dateAdded
        self.artworkPath = artworkPath
    }

    var displayArtist: String {
        return artistName ?? "Unknown Artist"
    }

    var displayYear: String {
        if let year = year {
            return String(year)
        }
        return ""
    }

    var formattedDuration: String {
        return totalDuration.formattedDuration
    }
}
