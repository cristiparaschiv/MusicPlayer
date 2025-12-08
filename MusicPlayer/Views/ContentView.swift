import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarItem? = .home
    @State private var showQueue = false

    var body: some View {
        if MediaScannerManager.shared.isLibraryEmpty() {
            EmptyMusicLibraryView(context: .mainWindow)
        } else {
            VStack(spacing: 0) {
                // Main content area (navigation + now playing sidebar)
                HStack(spacing: 0) {
                    // Left content - Navigation split view
                    NavigationSplitView {
                        Sidebar(selection: $selection)
                    } detail: {
                        NavigationStack {
                            switch selection {
                            case .home:
                                HomeView()
                            case .albums:
                                AlbumsView()
                            case .artists:
                                ArtistsView()
                            case .songs:
                                SongsView()
                            case .favorites:
                                PlaylistView(favorites: true)
                                    .id("favorites")
                            case .playlist(let playlist):
                                PlaylistView(playlist: playlist)
                                    .id(playlist.id)
                            case .none:
                                Text("Select something from the sidebar")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Right sidebar - Now Playing / Queue
                    Group {
                        if showQueue {
                            QueueView()
                        } else {
                            NowPlayingView()
                        }
                    }
                    .frame(width: 280)
                }

                Divider()

                // Bottom player control bar
                PlayerControlBar(showQueue: $showQueue)
                    .frame(height: 120)
            }
        }
    }
}
