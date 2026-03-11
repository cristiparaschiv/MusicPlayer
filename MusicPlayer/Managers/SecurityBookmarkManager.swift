import Foundation
import AppKit

class SecurityBookmarkManager {
    static let shared = SecurityBookmarkManager()

    private let bookmarksKey = "SecurityScopedBookmarks"
    private var activeBookmarks: [URL: URL] = [:] // Original URL -> Security-scoped URL
    private let lock = NSLock()

    private let bookmarkMigrationKey = "BookmarkMigratedToReadWrite_v2"

    private init() {
        resolveAllBookmarks()
    }

    /// Check if bookmarks need re-granting for write access
    var needsWriteAccessMigration: Bool {
        !UserDefaults.standard.bool(forKey: bookmarkMigrationKey)
    }

    /// Prompt user to re-select folders for read-write access
    func migrateToReadWrite(completion: @escaping (Bool) -> Void) {
        let paths = getAllBookmarkPaths()
        guard !paths.isEmpty else {
            UserDefaults.standard.set(true, forKey: bookmarkMigrationKey)
            completion(true)
            return
        }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Update Folder Access"
            alert.informativeText = "To enable metadata editing, the app needs to re-authorize access to your music folders. You'll be asked to select each folder again."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Update Now")
            alert.addButton(withTitle: "Later")

            guard alert.runModal() == .alertFirstButtonReturn else {
                completion(false)
                return
            }

            self.reauthorizePaths(paths, index: 0) {
                UserDefaults.standard.set(true, forKey: self.bookmarkMigrationKey)
                completion(true)
            }
        }
    }

    private func reauthorizePaths(_ paths: [String], index: Int, completion: @escaping () -> Void) {
        guard index < paths.count else {
            completion()
            return
        }

        let path = paths[index]
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Grant Access"
        panel.message = "Please re-select this folder to enable editing:\n\(path)"
        panel.directoryURL = URL(fileURLWithPath: path)

        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                _ = self?.createBookmark(for: url)
            }
            self?.reauthorizePaths(paths, index: index + 1, completion: completion)
        }
    }

    // MARK: - Public Methods

    /// Create and save a security-scoped bookmark for a URL
    func createBookmark(for url: URL) -> Bool {
        do {
            // Create bookmark data
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            // Save to UserDefaults
            var bookmarks = loadBookmarks()
            bookmarks[url.path] = bookmarkData
            saveBookmarks(bookmarks)

            // Start accessing immediately
            if url.startAccessingSecurityScopedResource() {
                lock.lock()
                activeBookmarks[url] = url
                lock.unlock()
                return true
            } else {
                return false
            }
        } catch {
            #if DEBUG
            print("Failed to create bookmark for \(url.path): \(error)")
            #endif
            return false
        }
    }

    /// Remove a security-scoped bookmark
    func removeBookmark(for path: String) {
        // Stop accessing if active
        lock.lock()
        if let url = activeBookmarks.first(where: { $0.key.path == path })?.key {
            url.stopAccessingSecurityScopedResource()
            activeBookmarks.removeValue(forKey: url)
        }
        lock.unlock()

        // Remove from storage
        var bookmarks = loadBookmarks()
        bookmarks.removeValue(forKey: path)
        saveBookmarks(bookmarks)
    }

    /// Resolve all saved bookmarks (call on app launch)
    func resolveAllBookmarks() {
        let bookmarks = loadBookmarks()

        for (path, bookmarkData) in bookmarks {
            resolveBookmark(path: path, data: bookmarkData)
        }
    }

    /// Check if a path has an active bookmark
    func hasActiveBookmark(for path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeBookmarks.keys.contains(where: { $0.path == path })
    }

    /// Get all active bookmark paths
    func getAllBookmarkPaths() -> [String] {
        lock.lock()
        defer { lock.unlock() }
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
                lock.lock()
                activeBookmarks[url] = url
                lock.unlock()

                // If bookmark is stale, recreate it
                if isStale {
                    _ = createBookmark(for: url)
                }
            }
        } catch {
            #if DEBUG
            print("Failed to resolve bookmark for \(path): \(error)")
            #endif
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
        lock.lock()
        for url in activeBookmarks.keys {
            url.stopAccessingSecurityScopedResource()
        }
        lock.unlock()
    }
}
