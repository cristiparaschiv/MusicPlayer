import Foundation
import AppKit

class SecurityBookmarkManager {
    static let shared = SecurityBookmarkManager()

    private let bookmarksKey = "SecurityScopedBookmarks"
    private var activeBookmarks: [URL: URL] = [:] // Original URL -> Security-scoped URL

    private init() {
        resolveAllBookmarks()
    }

    // MARK: - Public Methods

    /// Create and save a security-scoped bookmark for a URL
    func createBookmark(for url: URL) -> Bool {
        do {
            // Create bookmark data
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            // Save to UserDefaults
            var bookmarks = loadBookmarks()
            bookmarks[url.path] = bookmarkData
            saveBookmarks(bookmarks)

            // Start accessing immediately
            if url.startAccessingSecurityScopedResource() {
                activeBookmarks[url] = url
                print("✅ Created and started accessing bookmark for: \(url.path)")
                return true
            } else {
                print("⚠️ Failed to start accessing security-scoped resource: \(url.path)")
                return false
            }
        } catch {
            print("❌ Failed to create bookmark for \(url.path): \(error)")
            return false
        }
    }

    /// Remove a security-scoped bookmark
    func removeBookmark(for path: String) {
        // Stop accessing if active
        if let url = activeBookmarks.first(where: { $0.key.path == path })?.key {
            url.stopAccessingSecurityScopedResource()
            activeBookmarks.removeValue(forKey: url)
        }

        // Remove from storage
        var bookmarks = loadBookmarks()
        bookmarks.removeValue(forKey: path)
        saveBookmarks(bookmarks)

        print("🗑️ Removed bookmark for: \(path)")
    }

    /// Resolve all saved bookmarks (call on app launch)
    func resolveAllBookmarks() {
        let bookmarks = loadBookmarks()

        for (path, bookmarkData) in bookmarks {
            resolveBookmark(path: path, data: bookmarkData)
        }

        print("📂 Resolved \(activeBookmarks.count) security-scoped bookmarks")
    }

    /// Check if a path has an active bookmark
    func hasActiveBookmark(for path: String) -> Bool {
        return activeBookmarks.keys.contains(where: { $0.path == path })
    }

    /// Get all active bookmark paths
    func getAllBookmarkPaths() -> [String] {
        return Array(activeBookmarks.keys.map { $0.path })
    }

    // MARK: - Private Methods

    private func resolveBookmark(path: String, data: Data) {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // Start accessing the security-scoped resource
            if url.startAccessingSecurityScopedResource() {
                activeBookmarks[url] = url
                print("✅ Resolved bookmark for: \(path)")

                // If bookmark is stale, recreate it
                if isStale {
                    print("⚠️ Bookmark is stale, recreating: \(path)")
                    _ = createBookmark(for: url)
                }
            } else {
                print("⚠️ Failed to start accessing resolved bookmark: \(path)")
            }
        } catch {
            print("❌ Failed to resolve bookmark for \(path): \(error)")
            // Remove invalid bookmark
            var bookmarks = loadBookmarks()
            bookmarks.removeValue(forKey: path)
            saveBookmarks(bookmarks)
        }
    }

    private func loadBookmarks() -> [String: Data] {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return [:]
        }
        return bookmarks
    }

    private func saveBookmarks(_ bookmarks: [String: Data]) {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }

    // MARK: - Cleanup

    deinit {
        // Stop accessing all security-scoped resources
        for url in activeBookmarks.keys {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
