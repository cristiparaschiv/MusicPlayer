import Foundation

enum SidebarItem: Hashable {
    case home
    case albums
    case artists
    case songs
    case favorites
    case search
    case playlist(Playlist)

    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home): return true
        case (.albums, .albums): return true
        case (.artists, .artists): return true
        case (.songs, .songs): return true
        case (.favorites, .favorites): return true
        case (.search, .search): return true
        case (.playlist(let lhs), .playlist(let rhs)): return lhs.id == rhs.id
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .home: hasher.combine("home")
        case .albums: hasher.combine("albums")
        case .artists: hasher.combine("artists")
        case .songs: hasher.combine("songs")
        case .favorites: hasher.combine("favorites")
        case .search: hasher.combine("search")
        case .playlist(let playlist): hasher.combine("playlist-\(playlist.id)")
        }
    }
}
