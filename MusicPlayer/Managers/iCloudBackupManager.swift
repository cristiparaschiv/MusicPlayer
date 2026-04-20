import Foundation

class iCloudBackupManager {
    static let shared = iCloudBackupManager()

    private let maxBackups = 3
    private let backupFolder = "DatabaseBackups"
    private let queue = DispatchQueue(label: "com.orangemusicplayer.icloudbackup", qos: .utility)

    private init() {}

    // MARK: - Public

    /// Whether iCloud is available for this app
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Backup the database to iCloud. Safe to call from any thread.
    func backupAfterScan() {
        queue.async { [weak self] in
            self?.performBackup()
        }
    }

    /// List available backups, newest first
    func listBackups() -> [BackupInfo] {
        guard let container = iCloudBackupDirectory() else { return [] }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: container, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "sqlite" }
            .compactMap { url -> BackupInfo? in
                let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let date = attrs?.contentModificationDate ?? Date.distantPast
                let size = attrs?.fileSize ?? 0
                return BackupInfo(url: url, date: date, size: size)
            }
            .sorted { $0.date > $1.date }
    }

    /// Restore a backup, replacing the current database.
    /// Returns true on success. The app should be restarted after this.
    func restore(from backup: BackupInfo) -> Bool {
        let dbPath = FileManager.default.applicationSupportDirectory()
            .appendingPathComponent(Constants.databaseName)

        // Close the current database connection
        DatabaseManager.shared.close()

        let fm = FileManager.default

        // Remove current DB and WAL/SHM files
        let walPath = dbPath.appendingPathExtension("wal")
        let shmPath = dbPath.appendingPathExtension("shm")

        do {
            // Back up current DB locally before overwriting, just in case
            let localBackup = dbPath.deletingLastPathComponent().appendingPathComponent("pre-restore-backup.sqlite")
            try? fm.removeItem(at: localBackup)
            try? fm.copyItem(at: dbPath, to: localBackup)

            try? fm.removeItem(at: walPath)
            try? fm.removeItem(at: shmPath)
            try fm.removeItem(at: dbPath)
            try fm.copyItem(at: backup.url, to: dbPath)
            return true
        } catch {
            #if DEBUG
            print("[iCloudBackup] Restore failed: \(error)")
            #endif
            return false
        }
    }

    // MARK: - Private

    private func performBackup() {
        guard let container = iCloudBackupDirectory() else {
            #if DEBUG
            print("[iCloudBackup] iCloud container not available, skipping backup")
            #endif
            return
        }

        let fm = FileManager.default
        let dbPath = fm.applicationSupportDirectory()
            .appendingPathComponent(Constants.databaseName)

        guard fm.fileExists(atPath: dbPath.path) else { return }

        // Check there are actual tracks before backing up (don't back up an empty DB)
        let trackCount = DatabaseManager.shared.query(sql: "SELECT COUNT(*) as cnt FROM tracks")
        let count = (trackCount.first?["cnt"] as? Int64) ?? 0
        guard count > 0 else {
            #if DEBUG
            print("[iCloudBackup] Skipping backup — database has no tracks")
            #endif
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupName = "OrangeMusicPlayer_\(timestamp).sqlite"
        let destination = container.appendingPathComponent(backupName)

        do {
            try fm.copyItem(at: dbPath, to: destination)
            #if DEBUG
            print("[iCloudBackup] Backed up to \(destination.lastPathComponent)")
            #endif
            pruneOldBackups(in: container)
        } catch {
            #if DEBUG
            print("[iCloudBackup] Backup failed: \(error)")
            #endif
        }
    }

    private func pruneOldBackups(in directory: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }

        let backups = files
            .filter { $0.pathExtension == "sqlite" && $0.lastPathComponent.hasPrefix("OrangeMusicPlayer_") }
            .sorted { url1, url2 in
                let d1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let d2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return d1 > d2
            }

        if backups.count > maxBackups {
            for backup in backups.dropFirst(maxBackups) {
                try? fm.removeItem(at: backup)
                #if DEBUG
                print("[iCloudBackup] Pruned old backup: \(backup.lastPathComponent)")
                #endif
            }
        }
    }

    private func iCloudBackupDirectory() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }

        let backupDir = container.appendingPathComponent("Documents").appendingPathComponent(backupFolder)
        let fm = FileManager.default
        if !fm.fileExists(atPath: backupDir.path) {
            try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        }
        return backupDir
    }
}

// MARK: - BackupInfo

struct BackupInfo: Identifiable {
    let url: URL
    let date: Date
    let size: Int

    var id: URL { url }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
