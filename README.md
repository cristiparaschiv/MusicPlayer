# Orange Music Player

A modern, native music player for macOS built with SwiftUI and SFBAudioEngine.

<p align="center">
<img src="screenshots/appstore.png" height="200" width="200" />
</p>

![Home](screenshots/Home.png)

## Features

Library Management

  - Import music from local folders
  - Automatic metadata extraction (title, artist, album, year, track number)
  - Album artwork display
  - Smart library scanning with change detection

Playback

  - High-quality audio playback via SFBAudioEngine
  - Support for multiple formats: FLAC, MP3, AAC, ALAC, WAV, AIFF, and more
  - Crossfade between tracks with adjustable duration (1-10 seconds)
  - Gapless playback for seamless album listening
  - Shuffle and repeat modes (off, all, one)
  - Audio output device selection

Organization

  - Browse by Albums, Artists, or Songs
  - Create and manage playlists
  - Mark tracks as favorites
  - Recently Played and Frequently Played sections on Home

User Experience

  - Global search across tracks, albums, and artists
  - Double-click to play tracks
  - Keyboard shortcuts for common actions
  - Dynamic color theming based on album artwork
  - Clean, native macOS interface

Keyboard Shortcuts

  | Action         | Shortcut |
  |----------------|----------|
  | Play/Pause     | Space    |
  | Next Track     | ⌘ →      |
  | Previous Track | ⌘ ←      |
  | Volume Up      | ⌘ ↑      |
  | Volume Down    | ⌘ ↓      |
  | Toggle Shuffle | ⌘ S      |
  | Toggle Repeat  | ⌘ R      |
  | Search         | ⌘ F      |

## Requirements

  - macOS 14.0 (Sonoma) or later
  - Apple Silicon or Intel Mac

## Building from Source

  1. Clone the repository
  2. Open MusicPlayer.xcodeproj in Xcode 15 or later
  3. Build and run (⌘R)

## Dependencies

  - https://github.com/sbooth/SFBAudioEngine - Audio playback engine (via Swift Package Manager)

## Technology Stack

  - SwiftUI - User interface
  - SFBAudioEngine - High-quality audio decoding and playback
  - AVFoundation - Audio engine and mixer management
  - CoreAudio - Audio device management
  - SQLite - Local database for library and playlists
  - Core Image - Album artwork color extraction

## License

  © 2024-2025 Orange Music Player. All rights reserved.

## Acknowledgments

  - https://github.com/sbooth/SFBAudioEngine by Stephen F. Booth
