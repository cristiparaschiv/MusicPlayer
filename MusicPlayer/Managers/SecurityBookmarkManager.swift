import Foundation
import AppKit
import Security

class SecurityBookmarkManager {
    static let shared = SecurityBookmarkManager()

    private let bookmarksKey = "SecurityScopedBookmarks"
    private let keychainService = "com.orangemusicplayer.bookmarks"
    private let keychainAccount = "security-scoped-bookmarks"
    private let keychainMigrationKey = "BookmarkMigratedToKeychain_v1"
    private var activeBookmarks: [URL: URL] = [:] // Original URL -> Security-scoped URL
    private(set) var failedBookmarkPaths: [String] = [] // Paths that failed to resolve
    private let lock = NSLock()
    private let storageLock = NSLock() // Protects load-modify-save sequences

    private let bookmarkMigrationKey = "BookmarkMigratedToReadWrite_v2"

    private init() {
        migrateToKeychainIfNeeded()
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

            // Save to UserDefaults (atomic load-modify-save)
            storageLock.lock()
            var bookmarks = loadBookmarks()
            bookmarks[url.path] = bookmarkData
            saveBookmarks(bookmarks)
            storageLock.unlock()

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

        // Remove from storage (atomic load-modify-save)
        storageLock.lock()
        var bookmarks = loadBookmarks()
        bookmarks.removeValue(forKey: path)
        saveBookmarks(bookmarks)
        storageLock.unlock()
    }

    /// Resolve all saved bookmarks (call on app launch)
    func resolveAllBookmarks() {
        let bookmarks = loadBookmarks()

        lock.lock()
        failedBookmarkPaths.removeAll()
        lock.unlock()

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
            } else {
                lock.lock()
                failedBookmarkPaths.append(path)
                lock.unlock()
            }
        } catch {
            #if DEBUG
            print("Failed to resolve bookmark for \(path): \(error)")
            #endif
            // Track the failure so the UI can inform the user
            lock.lock()
            failedBookmarkPaths.append(path)
            lock.unlock()
            // Remove invalid bookmark (atomic load-modify-save)
            storageLock.lock()
            var bookmarks = loadBookmarks()
            bookmarks.removeValue(forKey: path)
            saveBookmarks(bookmarks)
            storageLock.unlock()
        }
    }

    // MARK: - Keychain Storage

    private func loadBookmarks() -> [String: Data] {
        // Try Keychain first
        if let data = loadFromKeychain() {
            return data
        }
        // Fallback to UserDefaults (pre-migration)
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return [:]
        }
        return bookmarks
    }

    private func saveBookmarks(_ bookmarks: [String: Data]) {
        // Save to Keychain
        saveToKeychain(bookmarks)
    }

    private func migrateToKeychainIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: keychainMigrationKey) else { return }

        // Load from UserDefaults if present
        if let data = UserDefaults.standard.data(forKey: bookmarksKey),
           let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data),
           !bookmarks.isEmpty {
            saveToKeychain(bookmarks)
            // Remove from UserDefaults after successful migration
            UserDefaults.standard.removeObject(forKey: bookmarksKey)
        }
        UserDefaults.standard.set(true, forKey: keychainMigrationKey)
    }

    private func loadFromKeychain() -> [String: Data]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode([String: Data].self, from: data)
    }

    private func saveToKeychain(_ bookmarks: [String: Data]) {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }

        // Try to update first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist, add it
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
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
