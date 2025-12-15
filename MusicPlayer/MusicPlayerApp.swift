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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            PlaybackCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Playback Commands

struct PlaybackCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Divider()
        }

        CommandMenu("Playback") {
            Button("Play/Pause") {
                NowPlayingManager.shared.togglePlayPause()
            }
            .keyboardShortcut("p", modifiers: .command)

            Divider()

            Button("Next Track") {
                NowPlayingManager.shared.next()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Button("Previous Track") {
                NowPlayingManager.shared.previous()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Divider()

            Button("Volume Up") {
                PlayerManager.shared.increaseVolume(by: 0.1)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Volume Down") {
                PlayerManager.shared.decreaseVolume(by: 0.1)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)

            Divider()

            Button("Toggle Queue") {
                NotificationCenter.default.post(
                    name: Notification.Name("ToggleQueue"),
                    object: nil
                )
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
        }
    }
}
