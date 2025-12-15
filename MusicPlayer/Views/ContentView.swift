import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarItem? = .home
    @State private var showQueue = false
    @StateObject private var searchManager = SearchManager()
    @State private var localEventMonitor: Any?

    var body: some View {
        if MediaScannerManager.shared.isLibraryEmpty() {
            EmptyMusicLibraryView(context: .mainWindow)
        } else {
            VStack(spacing: 0) {
                // Main content area (navigation + now playing sidebar)
                HStack(spacing: 0) {
                    // Left content - Navigation split view
                    NavigationSplitView(columnVisibility: .constant(.all)) {
                        Sidebar(selection: $selection)
                            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
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
                            case .search:
                                SearchResultsView()
                                    .environmentObject(searchManager)
                            case .playlist(let playlist):
                                PlaylistView(playlist: playlist)
                                    .id(playlist.id)
                            case .none:
                                Text("Select something from the sidebar")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toolbar {
                            ToolbarItem(placement: .automatic) {
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 13))
                                    TextField("Search tracks, albums, artists...", text: $searchManager.searchText)
                                        .textFieldStyle(.plain)
                                        .frame(width: 220)
                                        .onChange(of: searchManager.searchText) { _, newValue in
                                            searchManager.performSearch()
                                            if !newValue.isEmpty && selection != .search {
                                                selection = .search
                                            }
                                        }

                                    if !searchManager.searchText.isEmpty {
                                        Button(action: {
                                            searchManager.clearSearch()
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                                .font(.system(size: 12))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
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
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleQueue"))) { _ in
                withAnimation {
                    showQueue.toggle()
                }
            }
            .onAppear {
                setupKeyboardShortcuts()
            }
            .onDisappear {
                removeKeyboardShortcuts()
            }
        }
    }

    private func setupKeyboardShortcuts() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Check if Space bar is pressed and no text field is focused
            if event.keyCode == 49 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                // Check if a text field or text view is the first responder
                if let firstResponder = NSApp.keyWindow?.firstResponder,
                   !(firstResponder is NSText) && !(firstResponder is NSTextView) {
                    NowPlayingManager.shared.togglePlayPause()
                    return nil // Consume the event
                }
            }
            return event
        }
    }

    private func removeKeyboardShortcuts() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
}
