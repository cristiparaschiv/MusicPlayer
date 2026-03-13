import Foundation

enum SidebarItem: Hashable {
    case home
    case albums
    case artists
    case songs
    case favorites
    case recentlyAdded
    case search
    case stats
    case folders
    case columnBrowser
    case playlist(Playlist)
    case radio(RadioStation)

    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home): return true
        case (.albums, .albums): return true
        case (.artists, .artists): return true
        case (.songs, .songs): return true
        case (.favorites, .favorites): return true
        case (.recentlyAdded, .recentlyAdded): return true
        case (.search, .search): return true
        case (.stats, .stats): return true
        case (.folders, .folders): return true
        case (.columnBrowser, .columnBrowser): return true
        case (.playlist(let lhs), .playlist(let rhs)): return lhs.id == rhs.id
        case (.radio(let lhs), .radio(let rhs)): return lhs.id == rhs.id
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
        case .recentlyAdded: hasher.combine("recentlyAdded")
        case .search: hasher.combine("search")
        case .stats: hasher.combine("stats")
        case .folders: hasher.combine("folders")
        case .columnBrowser: hasher.combine("columnBrowser")
        case .playlist(let playlist): hasher.combine("playlist-\(playlist.id)")
        case .radio(let station): hasher.combine("radio-\(station.id)")
        }
    }
}
