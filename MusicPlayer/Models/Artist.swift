import Foundation

struct Artist {
    let id: Int64
    let name: String
    let nameSort: String
    let albumCount: Int
    let trackCount: Int
    let profileImagePath: String?

    init(id: Int64,
         name: String,
         nameSort: String? = nil,
         albumCount: Int = 0,
         trackCount: Int = 0,
         profileImagePath: String? = nil) {
        self.id = id
        self.name = name
        self.nameSort = nameSort ?? name.sortKey
        self.albumCount = albumCount
        self.trackCount = trackCount
        self.profileImagePath = profileImagePath
    }
}
