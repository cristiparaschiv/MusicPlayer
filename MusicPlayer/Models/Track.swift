import Foundation

struct Track {
    let id: Int64
    let title: String
    let titleSort: String
    let artistId: Int64?
    let artistName: String?
    let albumId: Int64?
    let albumTitle: String?
    let albumArtistName: String?
    let trackNumber: Int?
    let discNumber: Int?
    let year: Int?
    let genreId: Int64?
    let genreName: String?
    let composerId: Int64?
    let composerName: String?
    let duration: TimeInterval
    let bitrate: Int?
    let sampleRate: Int?
    let filePath: String
    let fileSize: Int64
    let dateAdded: Date
    let dateModified: Date
    let lastPlayed: Date?
    let playCount: Int
    let rating: Int?
    let isFavorite: Bool
    let hasArtwork: Bool

    init(id: Int64,
         title: String,
         titleSort: String? = nil,
         artistId: Int64? = nil,
         artistName: String? = nil,
         albumId: Int64? = nil,
         albumTitle: String? = nil,
         albumArtistName: String? = nil,
         trackNumber: Int? = nil,
         discNumber: Int? = nil,
         year: Int? = nil,
         genreId: Int64? = nil,
         genreName: String? = nil,
         composerId: Int64? = nil,
         composerName: String? = nil,
         duration: TimeInterval,
         bitrate: Int? = nil,
         sampleRate: Int? = nil,
         filePath: String,
         fileSize: Int64,
         dateAdded: Date = Date(),
         dateModified: Date = Date(),
         lastPlayed: Date? = nil,
         playCount: Int = 0,
         rating: Int? = nil,
         isFavorite: Bool = false,
         hasArtwork: Bool = false) {
        self.id = id
        self.title = title
        self.titleSort = titleSort ?? title.sortKey
        self.artistId = artistId
        self.artistName = artistName
        self.albumId = albumId
        self.albumTitle = albumTitle
        self.albumArtistName = albumArtistName
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.year = year
        self.genreId = genreId
        self.genreName = genreName
        self.composerId = composerId
        self.composerName = composerName
        self.duration = duration
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.filePath = filePath
        self.fileSize = fileSize
        self.dateAdded = dateAdded
        self.dateModified = dateModified
        self.lastPlayed = lastPlayed
        self.playCount = playCount
        self.rating = rating
        self.isFavorite = isFavorite
        self.hasArtwork = hasArtwork
    }

    var displayArtist: String {
        return albumArtistName ?? artistName ?? "Unknown Artist"
    }

    var displayAlbum: String {
        return albumTitle ?? "Unknown Album"
    }

    var formattedDuration: String {
        return duration.formattedDuration
    }
}
