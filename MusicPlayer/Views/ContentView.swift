import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selection: SidebarItem? = .home
    @State private var showQueue = false
    @AppStorage("showNowPlayingPanel") private var showNowPlaying = true
    @StateObject private var searchManager = SearchManager()
    @State private var localEventMonitor: Any?
    @State private var isLibraryEmpty: Bool = true
    @State private var showSearchDropdown = false
    @State private var navigationPath = NavigationPath()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showKeyboardShortcuts = false
    @ObservedObject private var nowPlaying = NowPlayingManager.shared

    var body: some View {
        if isLibraryEmpty {
            EmptyMusicLibraryView(context: .mainWindow)
                .onAppear {
                    isLibraryEmpty = MediaScannerManager.shared.isLibraryEmpty()
                }
                .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
                    isLibraryEmpty = MediaScannerManager.shared.isLibraryEmpty()
                }
                .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryPathsChanged)) { _ in
                    // Check after a short delay to allow paths to be added
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isLibraryEmpty = MediaScannerManager.shared.isLibraryEmpty()
                    }
                }
        } else {
            VStack(spacing: 0) {
                // Main content area (navigation + now playing sidebar)
                HStack(spacing: 0) {
                    // Left content - Navigation split view
                    NavigationSplitView(columnVisibility: $columnVisibility) {
                        Sidebar(selection: $selection)
                            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
                    } detail: {
                        NavigationStack(path: $navigationPath) {
                            Group {
                                switch selection {
                                case .home:
                                    HomeView()
                                        .navigationTitle("Home")
                                case .albums:
                                    AlbumsView()
                                        .navigationTitle("Albums")
                                case .artists:
                                    ArtistsView()
                                        .navigationTitle("Artists")
                                case .songs:
                                    SongsView()
                                        .navigationTitle("Songs")
                                case .favorites:
                                    PlaylistView(favorites: true)
                                        .id("favorites")
                                        .navigationTitle("Liked Songs")
                                case .recentlyAdded:
                                    RecentlyAddedView()
                                        .navigationTitle("Recently Added")
                                case .search:
                                    SearchResultsView()
                                        .environmentObject(searchManager)
                                        .navigationTitle("Search")
                                case .stats:
                                    StatsView()
                                        .navigationTitle("Statistics")
                                case .folders:
                                    FolderBrowserView()
                                        .navigationTitle("Folders")
                                case .columnBrowser:
                                    ColumnBrowserView()
                                        .navigationTitle("Browser")
                                case .radio(let station):
                                    RadioStationView(station: station)
                                        .id(station.id)
                                        .navigationTitle(station.name)
                                case .playlist(let playlist):
                                    PlaylistView(playlist: playlist)
                                        .id(playlist.id)
                                        .navigationTitle(playlist.name)
                                case .recentlyOpened:
                                    RecentlyOpenedView()
                                        .navigationTitle("Recently Opened")
                                case .scripts:
                                    ScriptsView()
                                        .navigationTitle("Scripts")
                                case .none:
                                    Text("Select something from the sidebar")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .navigationDestination(for: Artist.self) { artist in
                                ArtistDetailView(artist: artist)
                            }
                            .navigationDestination(for: Album.self) { album in
                                AlbumDetailView(album: album)
                            }
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            SearchTextField(text: $searchManager.searchText, placeholder: "Search tracks, albums, artists...")
                                .frame(width: 240)
                                .onChange(of: searchManager.searchText) { _, newValue in
                                    searchManager.performSearch()
                                    if !newValue.isEmpty {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            showSearchDropdown = true
                                        }
                                        // Auto-switch sidebar to search view
                                        if selection != .search {
                                            selection = .search
                                        }
                                    } else {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            showSearchDropdown = false
                                        }
                                    }
                                }
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if showSearchDropdown && !searchManager.searchText.isEmpty {
                            SearchDropdownView(
                                searchManager: searchManager,
                                onTrackSelected: { track in
                                    PlayerManager.shared.play(track: track)
                                    dismissSearch()
                                },
                                onAlbumSelected: { album in
                                    dismissSearch()
                                    navigationPath.append(album)
                                },
                                onArtistSelected: { artist in
                                    dismissSearch()
                                    navigationPath.append(artist)
                                }
                            )
                            .padding(.top, 4)
                            .padding(.trailing, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .zIndex(100)
                        }
                    }
                    .onTapGesture {
                        if showSearchDropdown {
                            showSearchDropdown = false
                        }
                    }

                    // Right sidebar - Now Playing / Queue
                    if showNowPlaying || showQueue {
                        Divider()

                        Group {
                            if showQueue {
                                QueueView()
                            } else {
                                NowPlayingView()
                            }
                        }
                        .frame(width: 280)
                        .animation(.easeInOut(duration: 0.25), value: showQueue)
                    }
                }

                Divider()

                // Bottom player control bar
                PlayerControlBar(showQueue: $showQueue, showNowPlaying: $showNowPlaying)
            }
            .background {
                if let color = nowPlaying.dominantColor {
                    color.opacity(0.12)
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 0.5), value: nowPlaying.dominantColor != nil)
                }
            }
            .onChange(of: selection) { _, newValue in
                if newValue != .search && showSearchDropdown {
                    showSearchDropdown = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleQueue"))) { _ in
                withAnimation {
                    showQueue.toggle()
                }
            }
            .onAppear {
                setupKeyboardShortcuts()
                isLibraryEmpty = MediaScannerManager.shared.isLibraryEmpty()
            }
            .onDisappear {
                removeKeyboardShortcuts()
            }
            .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryDidUpdate)) { _ in
                isLibraryEmpty = MediaScannerManager.shared.isLibraryEmpty()
            }
            .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.libraryPathsChanged)) { _ in
                isLibraryEmpty = MediaScannerManager.shared.isLibraryEmpty()
            }
            .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.navigateToArtist)) { notification in
                if let artist = notification.object as? Artist {
                    navigationPath = NavigationPath()
                    navigationPath.append(artist)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.navigateToAlbum)) { notification in
                if let album = notification.object as? Album {
                    navigationPath = NavigationPath()
                    navigationPath.append(album)
                }
            }
            .sheet(isPresented: $showKeyboardShortcuts) {
                KeyboardShortcutsView()
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleFileDrop(providers)
                return true
            }
        }
    }

    private func dismissSearch() {
        searchManager.clearSearch()
        showSearchDropdown = false
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                defer { group.leave() }
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                urls.append(url)
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            ExternalTrackManager.shared.importURLs(urls)
        }
    }

    private func setupKeyboardShortcuts() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Cmd+Shift+F for immersive mode
            if event.keyCode == 3 && flags == [.command, .shift] {
                ImmersiveWindowManager.shared.toggle()
                return nil
            }

            // Cmd+Shift+M for mini player
            if event.keyCode == 46 && flags == [.command, .shift] {
                MiniPlayerWindowManager.shared.toggle()
                return nil
            }

            // Cmd+F for search focus
            if event.keyCode == 3 && flags == .command {
                showSearchDropdown = true
                return nil
            }

            // Cmd+/ for keyboard shortcuts
            if event.keyCode == 44 && flags == .command {
                showKeyboardShortcuts = true
                return nil
            }

            // Check if Space bar is pressed and no text field is focused
            if event.keyCode == 49 && flags.isEmpty {
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
