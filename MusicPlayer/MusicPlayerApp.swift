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

        // Initialize system media integration (media keys + Now Playing info)
        _ = SystemMediaIntegrationManager.shared

        // Start remote control server if enabled
        RemoteServerManager.shared.startIfEnabled()

        // Initialize scripting engine
        ScriptingEngine.shared.start()

        // Initialize script console window manager
        _ = ScriptConsoleWindowManager.shared

        // Use overlay (thin, auto-hiding) scrollbars globally
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    @AppStorage("appAppearance") private var appAppearance: String = "system"

    private var colorScheme: ColorScheme? {
        switch appAppearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 600)
                .preferredColorScheme(colorScheme)
                .onOpenURL { url in
                    ExternalTrackManager.shared.importURLs([url])
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            PlaybackCommands()
            ScriptsCommands()
        }

        Settings {
            SettingsView()
                .preferredColorScheme(colorScheme)
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

            Divider()

            Button("Mini Player") {
                MiniPlayerWindowManager.shared.toggle()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button("Audio Effects") {
                AudioEffectsWindowManager.shared.toggle()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Immersive Mode") {
                ImmersiveWindowManager.shared.toggle()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Scripts Commands

struct ScriptsCommands: Commands {
    @ObservedObject private var engine = ScriptingEngine.shared

    var body: some Commands {
        CommandMenu("Scripts") {
            ForEach(engine.scripts.filter { $0.isEnabled && $0.event == nil }) { script in
                Button(script.name) {
                    engine.runScript(id: script.id)
                }
            }

            if !engine.scripts.filter({ $0.isEnabled && $0.event == nil }).isEmpty {
                Divider()
            }

            Button("Open Scripts Folder") {
                engine.openScriptsFolder()
            }

            Divider()

            Button("Script Console") {
                ScriptConsoleWindowManager.shared.toggle()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
        }
    }
}
