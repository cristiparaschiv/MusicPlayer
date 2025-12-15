import Foundation

struct Constants {
    // Database
    static let databaseName = "OrangeMusicPlayer.sqlite"
    static let databaseVersion = 1

    // Cache
    static let artworkCacheDirectory = "ArtworkCache"
    static let lyricsCacheDirectory = "LyricsCache"
    static let maxCacheSizeMB = 500

    // API Keys (users should replace with their own)
    static let lastFMAPIKey = "3f01391362f7079266e1174b52de5b51"
    static let musicBrainzAppName = "OrangeMusicPlayer"
    static let musicBrainzVersion = "1.0"
    static let musicBrainzContact = "cristianv.paraschiv@gmail.com"

    // UI
    static let defaultWindowWidth: CGFloat = 1200
    static let defaultWindowHeight: CGFloat = 800
    static let sidebarWidth: CGFloat = 200
    static let nowPlayingPaneWidth: CGFloat = 300
    static let gridItemSize: CGFloat = 180
    static let artworkSize: CGFloat = 200

    // Audio
    static let defaultCrossfadeDuration: TimeInterval = 3.0
    static let defaultVolume: Float = 0.8

    // User Defaults Keys
    struct UserDefaultsKeys {
        static let mediaLibraryPaths = "mediaLibraryPaths"
        static let crossfadeEnabled = "crossfadeEnabled"
        static let crossfadeDuration = "crossfadeDuration"
        static let gaplessPlaybackEnabled = "gaplessPlaybackEnabled"
        static let shuffleEnabled = "shuffleEnabled"
        static let repeatMode = "repeatMode"
        static let volume = "volume"
    }

    // Notifications
    struct Notifications {
        static let trackDidChange = Notification.Name("trackDidChange")
        static let playbackStateChanged = Notification.Name("playbackStateChanged")
        static let playbackTimeChanged = Notification.Name("playbackTimeChanged")
        static let volumeChanged = Notification.Name("volumeChanged")
        static let trackFavoriteChanged = Notification.Name("trackFavoriteChanged")
        static let queueDidChange = Notification.Name("queueDidChange")
        static let repeatModeChanged = Notification.Name("repeatModeChanged")
        static let shuffleModeChanged = Notification.Name("shuffleModeChanged")
        static let libraryDidUpdate = Notification.Name("libraryDidUpdate")
        static let libraryPathsChanged = Notification.Name("libraryPathsChanged")
        static let playlistsChanged = Notification.Name("playlistsChanged")
        static let playlistContentChanged = Notification.Name("playlistContentChanged")
        static let artworkDidLoad = Notification.Name("artworkDidLoad")
        static let lyricsDidLoad = Notification.Name("lyricsDidLoad")
    }
}

enum Icons {
    // Music & Audio
    static let musicNote = "music.note"
    static let musicNoteList = "music.note.list"
    static let musicNoteHouse = "music.note.house"
    static let musicNoteHouseFill = "music.note.house.fill"
    static let speakerFill = "speaker.fill"
    static let speakerWave3 = "speaker.wave.3"
    static let speakerWave3Fill = "speaker.wave.3.fill"
    
    // Playback Controls
    static let star = "star"
    static let playFill = "play.fill"
    static let pauseFill = "pause.fill"
    static let playPauseFill = "playpause.fill"
    static let playCircleFill = "play.circle.fill"
    static let pauseCircleFill = "pause.circle.fill"
    static let backwardFill = "backward.fill"
    static let previousFIll = "backward.end.alt.fill"
    static let forwardFill = "forward.fill"
    static let nextFill = "forward.end.alt.fill"
    static let shuffleFill = "shuffle"
    static let repeatFill = "repeat"
    static let repeat1Fill = "repeat.1"
    static let volumeIncrease = "speaker.plus.fill"
    static let volumeDecrease = "speaker.minus.fill"
    
    // Navigation
    static let chevronRight = "chevron.right"
    static let chevronDown = "chevron.down"
    static let xmarkCircleFill = "xmark.circle.fill"
    
    // File & Folder
    static let folder = "folder"
    static let folderFill = "folder.fill"
    static let folderBadgePlus = "folder.badge.plus"
    static let folderFillBadgePlus = "folder.fill.badge.plus"
    static let folderFillBadgeMinus = "folder.fill.badge.minus"
    
    // UI Elements
    static let sparkles = "sparkles"
    static let settings = "gear"
    static let magnifyingGlass = "magnifyingglass"
    static let checkmarkSquareFill = "checkmark.square.fill"
    static let square = "square"
    static let trash = "trash"
    static let infoCircle = "info.circle"
    static let plusCircle = "plus.circle"
    static let checkForUpdates = "square.and.arrow.down"
    static let chartUptrendFill = "chart.line.uptrend.xyaxis.circle.fill"
    static let infoCircleFill = "info.circle.fill"
    static let plusCircleFill = "plus.circle.fill"
    static let minusSquareFill = "minus.square.fill"
    static let minusCircleFill = "minus.circle.fill"
    static let arrowClockwise = "arrow.clockwise"
    
    // Entity Icons
    static let personFill = "person.fill"
    static let person2Fill = "person.2.fill"
    static let person2CropSquareStackFill = "person.2.crop.square.stack.fill"
    static let person2Wave2Fill = "person.2.wave.2.fill"
    static let opticalDiscFill = "opticaldisc.fill"
    static let calendarBadgeClock = "calendar.badge.clock"
    static let calendarCircleFill = "calendar.circle.fill"
    
    // Smart Playlist Icons
    static let starFill = "star.fill"
    static let clockFill = "clock.fill"
    
    // Sort Icons
    static let sortAscending = "sort.ascending"
    static let sortDescending = "sort.descending"
    
    // Custom Icons (from project assets)
    static let customLossless = "custom.lossless"
    static let customMusicNoteRectangleStack = "custom.music.note.rectangle.stack"
    static let customMusicNoteRectangleStackFill = "custom.music.note.rectangle.stack.fill"
}


