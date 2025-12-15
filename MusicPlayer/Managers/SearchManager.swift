import Foundation
import SwiftUI
import Combine

struct SearchResults {
    var tracks: [Track] = []
    var albums: [Album] = []
    var artists: [Artist] = []

    var isEmpty: Bool {
        tracks.isEmpty && albums.isEmpty && artists.isEmpty
    }

    var hasMoreResults: Bool {
        tracks.count > 5 || albums.count > 5 || artists.count > 5
    }
}

@MainActor
class SearchManager: ObservableObject {
    @Published var searchText: String = ""
    @Published var searchResults: SearchResults = SearchResults()
    @Published var isSearching: Bool = false

    private var searchTask: Task<Void, Never>?
    private let trackDAO = TrackDAO()
    private let albumDAO = AlbumDAO()
    private let artistDAO = ArtistDAO()

    func performSearch() {
        // Cancel previous search task
        searchTask?.cancel()

        // Clear results if search text is empty
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = SearchResults()
            isSearching = false
            return
        }

        print("[SearchManager] performSearch called with query: '\(searchText)'")

        // Create new search task with debounce
        searchTask = Task { [weak self] in
            guard let self = self else { return }

            // Debounce: wait 300ms
            try? await Task.sleep(nanoseconds: 300_000_000)

            // Check if task was cancelled
            guard !Task.isCancelled else {
                print("[SearchManager] Task was cancelled")
                return
            }

            await MainActor.run {
                self.isSearching = true
            }

            let query = self.searchText
            print("[SearchManager] Searching for: '\(query)'")

            // Perform searches on background thread
            let tracks = await Task.detached {
                let results = self.trackDAO.search(query: query, limit: 100)
                print("[SearchManager] Track search returned \(results.count) results")
                return results
            }.value

            let albums = await Task.detached {
                let results = self.albumDAO.search(query: query, limit: 100)
                print("[SearchManager] Album search returned \(results.count) results")
                return results
            }.value

            let artists = await Task.detached {
                let results = self.artistDAO.search(query: query, limit: 100)
                print("[SearchManager] Artist search returned \(results.count) results")
                return results
            }.value

            // Check if task was cancelled before updating results
            guard !Task.isCancelled else {
                print("[SearchManager] Task was cancelled before updating results")
                return
            }

            print("[SearchManager] Total results - Tracks: \(tracks.count), Albums: \(albums.count), Artists: \(artists.count)")

            await MainActor.run {
                self.searchResults = SearchResults(
                    tracks: tracks,
                    albums: albums,
                    artists: artists
                )
                self.isSearching = false
                print("[SearchManager] Search results updated. isEmpty: \(self.searchResults.isEmpty)")
            }
        }
    }

    func clearSearch() {
        searchText = ""
        searchResults = SearchResults()
        isSearching = false
        searchTask?.cancel()
    }
}
