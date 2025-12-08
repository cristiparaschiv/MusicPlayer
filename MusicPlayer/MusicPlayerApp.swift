//
//  MusicPlayerApp.swift
//  MusicPlayer
//
//  Created by Cristi Paraschiv on 03.12.2025.
//

import SwiftUI

@main
struct MusicPlayerApp: App {
    init() {
        // Initialize database
        _ = DatabaseManager.shared

        // Resolve security-scoped bookmarks for library folders
        // This must happen before any file access attempts
        SecurityBookmarkManager.shared.resolveAllBookmarks()

        // Initialize now playing manager
        _ = NowPlayingManager.shared

        print("🎵 MusicPlayer initialized with \(SecurityBookmarkManager.shared.getAllBookmarkPaths().count) library folders")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        Settings {
            SettingsView()
        }
    }
}
