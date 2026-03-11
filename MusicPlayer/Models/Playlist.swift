import Foundation

struct Playlist: Hashable {
    let id: Int64
    let name: String
    let dateCreated: Date
    let dateModified: Date
    let isSmartPlaylist: Bool
    let smartCriteria: String?
    let trackCount: Int

    init(id: Int64,
         name: String,
         dateCreated: Date = Date(),
         dateModified: Date = Date(),
         isSmartPlaylist: Bool = false,
         smartCriteria: String? = nil,
         trackCount: Int = 0) {
        self.id = id
        self.name = name
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.isSmartPlaylist = isSmartPlaylist
        self.smartCriteria = smartCriteria
        self.trackCount = trackCount
    }

    static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
