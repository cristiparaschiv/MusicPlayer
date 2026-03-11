import Foundation

struct SmartPlaylistCriteria: Codable, Hashable {
    var matchAll: Bool = true  // true = AND, false = OR
    var rules: [SmartPlaylistRule] = []
    var limit: Int? = nil
    var orderBy: SmartPlaylistOrder = .dateAddedDesc
}

struct SmartPlaylistRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var field: SmartPlaylistField
    var comparison: SmartPlaylistComparison
    var value: String

    enum CodingKeys: String, CodingKey {
        case id, field, comparison, value
    }
}

enum SmartPlaylistField: String, Codable, CaseIterable, Hashable {
    case title
    case artistName = "artist_name"
    case albumTitle = "album_title"
    case genreName = "genre_name"
    case year
    case playCount = "play_count"
    case rating
    case duration
    case dateAdded = "date_added"
    case lastPlayed = "last_played"
    case isFavorite = "is_favorite"

    var displayName: String {
        switch self {
        case .title: return "Title"
        case .artistName: return "Artist"
        case .albumTitle: return "Album"
        case .genreName: return "Genre"
        case .year: return "Year"
        case .playCount: return "Play Count"
        case .rating: return "Rating"
        case .duration: return "Duration"
        case .dateAdded: return "Date Added"
        case .lastPlayed: return "Last Played"
        case .isFavorite: return "Is Favorite"
        }
    }

    var isText: Bool {
        switch self {
        case .title, .artistName, .albumTitle, .genreName: return true
        default: return false
        }
    }

    var isNumeric: Bool {
        switch self {
        case .year, .playCount, .rating, .duration: return true
        default: return false
        }
    }

    var isDate: Bool {
        switch self {
        case .dateAdded, .lastPlayed: return true
        default: return false
        }
    }

    var isBool: Bool {
        self == .isFavorite
    }

    var availableComparisons: [SmartPlaylistComparison] {
        if isText {
            return [.contains, .doesNotContain, .equals, .notEquals, .beginsWith, .endsWith]
        } else if isNumeric {
            return [.equals, .notEquals, .greaterThan, .lessThan, .greaterOrEqual, .lessOrEqual]
        } else if isDate {
            return [.inTheLast, .notInTheLast, .greaterThan, .lessThan]
        } else if isBool {
            return [.equals]
        }
        return [.equals]
    }
}

enum SmartPlaylistComparison: String, Codable, CaseIterable, Hashable {
    case contains
    case doesNotContain = "does_not_contain"
    case equals
    case notEquals = "not_equals"
    case beginsWith = "begins_with"
    case endsWith = "ends_with"
    case greaterThan = "greater_than"
    case lessThan = "less_than"
    case greaterOrEqual = "greater_or_equal"
    case lessOrEqual = "less_or_equal"
    case inTheLast = "in_the_last"
    case notInTheLast = "not_in_the_last"

    var displayName: String {
        switch self {
        case .contains: return "contains"
        case .doesNotContain: return "does not contain"
        case .equals: return "is"
        case .notEquals: return "is not"
        case .beginsWith: return "begins with"
        case .endsWith: return "ends with"
        case .greaterThan: return "greater than"
        case .lessThan: return "less than"
        case .greaterOrEqual: return "at least"
        case .lessOrEqual: return "at most"
        case .inTheLast: return "in the last"
        case .notInTheLast: return "not in the last"
        }
    }
}

enum SmartPlaylistOrder: String, Codable, CaseIterable, Hashable {
    case dateAddedDesc = "date_added_desc"
    case dateAddedAsc = "date_added_asc"
    case titleAsc = "title_asc"
    case artistAsc = "artist_asc"
    case playCountDesc = "play_count_desc"
    case random = "random"

    var displayName: String {
        switch self {
        case .dateAddedDesc: return "Date Added (Newest)"
        case .dateAddedAsc: return "Date Added (Oldest)"
        case .titleAsc: return "Title"
        case .artistAsc: return "Artist"
        case .playCountDesc: return "Most Played"
        case .random: return "Random"
        }
    }

    var sql: String {
        switch self {
        case .dateAddedDesc: return "date_added DESC"
        case .dateAddedAsc: return "date_added ASC"
        case .titleAsc: return "title_sort ASC"
        case .artistAsc: return "artist_name COLLATE NOCASE ASC"
        case .playCountDesc: return "play_count DESC"
        case .random: return "RANDOM()"
        }
    }
}
