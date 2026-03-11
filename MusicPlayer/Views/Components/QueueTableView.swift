import SwiftUI
import AppKit

struct QueueTableView: NSViewRepresentable {
    let tracks: [Track]
    var currentTrackIndex: Int?
    var onPlayTrack: ((Int) -> Void)?
    var onReorder: ((Int, Int) -> Void)?
    var onRemove: ((Int) -> Void)?

    private static let queueRowType = NSPasteboard.PasteboardType("com.orangemusicplayer.queuerow")

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.allowsMultipleSelection = false
        tableView.rowHeight = 48
        tableView.headerView = nil
        tableView.intercellSpacing = NSSize(width: 0, height: 0)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("queue"))
        col.minWidth = 200
        col.maxWidth = 10000
        tableView.addTableColumn(col)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.doubleAction = #selector(Coordinator.doubleClickRow(_:))
        tableView.target = context.coordinator

        // Drag and drop
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.registerForDraggedTypes([QueueTableView.queueRowType, TrackDragHelper.pasteboardType])

        // Context menu
        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let oldTracks = context.coordinator.parent.tracks
        let oldIndex = context.coordinator.parent.currentTrackIndex
        context.coordinator.parent = self

        let tracksChanged = tracks.map(\.id) != oldTracks.map(\.id)

        if tracksChanged {
            context.coordinator.tableView?.reloadData()
        } else if currentTrackIndex != oldIndex {
            // Only refresh the old and new current rows (no full reload, preserves artwork)
            var rowsToUpdate = IndexSet()
            if let old = oldIndex, old >= 0, old < tracks.count {
                rowsToUpdate.insert(old)
            }
            if let new = currentTrackIndex, new >= 0, new < tracks.count {
                rowsToUpdate.insert(new)
            }
            let allCols = IndexSet(integersIn: 0..<(context.coordinator.tableView?.numberOfColumns ?? 1))
            context.coordinator.tableView?.reloadData(forRowIndexes: rowsToUpdate, columnIndexes: allCols)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        var parent: QueueTableView
        weak var tableView: NSTableView?

        init(_ parent: QueueTableView) {
            self.parent = parent
            super.init()
        }

        // MARK: DataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.tracks.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.tracks.count else { return nil }
            let track = parent.tracks[row]
            let isCurrent = row == parent.currentTrackIndex

            let cellID = NSUserInterfaceItemIdentifier("QueueCell")
            let cell: QueueCellView
            if let existing = tableView.makeView(withIdentifier: cellID, owner: self) as? QueueCellView {
                cell = existing
            } else {
                cell = QueueCellView()
                cell.identifier = cellID
            }

            cell.configure(track: track, index: row, isCurrent: isCurrent)
            return cell
        }

        // MARK: Double-click

        @objc func doubleClickRow(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < parent.tracks.count else { return }
            parent.onPlayTrack?(row)
        }

        // MARK: Drag Source

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            let item = NSPasteboardItem()
            item.setString(String(row), forType: QueueTableView.queueRowType)
            return item
        }

        // MARK: Drop Target

        func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            if dropOperation == .on {
                tableView.setDropRow(row, dropOperation: .above)
            }

            let pasteboard = info.draggingPasteboard
            if pasteboard.availableType(from: [QueueTableView.queueRowType]) != nil {
                return .move
            }
            if pasteboard.availableType(from: [TrackDragHelper.pasteboardType]) != nil {
                return .copy
            }
            return []
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            let pasteboard = info.draggingPasteboard

            // Reorder within queue
            if let rowStr = pasteboard.string(forType: QueueTableView.queueRowType),
               let sourceRow = Int(rowStr) {
                var destRow = row
                if sourceRow < destRow {
                    destRow -= 1
                }
                if sourceRow != destRow {
                    parent.onReorder?(sourceRow, destRow)
                }
                return true
            }

            // Drop from TrackTableView
            if let encoded = pasteboard.string(forType: TrackDragHelper.pasteboardType),
               let trackIDs = TrackDragHelper.decode(encoded) {
                let dao = TrackDAO()
                let tracks = trackIDs.compactMap { dao.getById(id: $0) }
                if !tracks.isEmpty {
                    QueueManager.shared.addToQueue(tracks)
                }
                return true
            }

            return false
        }

        // MARK: Context Menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView = tableView else { return }

            let clickedRow = tableView.clickedRow
            guard clickedRow >= 0, clickedRow < parent.tracks.count else { return }
            let track = parent.tracks[clickedRow]

            // Play Now
            let playItem = NSMenuItem(title: "Play Now", action: #selector(contextPlayNow(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = clickedRow
            menu.addItem(playItem)

            menu.addItem(NSMenuItem.separator())

            // Favorites toggle
            let favTitle = track.isFavorite ? "Remove from Favorites" : "Add to Favorites"
            let favItem = NSMenuItem(title: favTitle, action: #selector(contextToggleFavorite(_:)), keyEquivalent: "")
            favItem.target = self
            favItem.representedObject = track
            menu.addItem(favItem)

            // Add to Playlist submenu
            let playlistSubmenu = NSMenu()
            let createItem = NSMenuItem(title: "Create New Playlist...", action: #selector(contextCreatePlaylistAndAdd(_:)), keyEquivalent: "")
            createItem.target = self
            createItem.representedObject = [track]
            playlistSubmenu.addItem(createItem)
            let playlists = PlaylistDAO().getAll()
            if !playlists.isEmpty {
                playlistSubmenu.addItem(NSMenuItem.separator())
                for playlist in playlists {
                    let pItem = NSMenuItem(title: playlist.name, action: #selector(contextAddToPlaylist(_:)), keyEquivalent: "")
                    pItem.target = self
                    pItem.representedObject = (track.id, playlist.id)
                    playlistSubmenu.addItem(pItem)
                }
            }
            let playlistMenuItem = NSMenuItem(title: "Add to Playlist", action: nil, keyEquivalent: "")
            playlistMenuItem.submenu = playlistSubmenu
            menu.addItem(playlistMenuItem)

            menu.addItem(NSMenuItem.separator())

            // Remove from Queue
            let removeItem = NSMenuItem(title: "Remove from Queue", action: #selector(contextRemoveFromQueue(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = clickedRow
            menu.addItem(removeItem)

            // Move Up/Down
            if clickedRow > 0 {
                let upItem = NSMenuItem(title: "Move Up", action: #selector(contextMoveUp(_:)), keyEquivalent: "")
                upItem.target = self
                upItem.representedObject = clickedRow
                menu.addItem(upItem)
            }
            if clickedRow < parent.tracks.count - 1 {
                let downItem = NSMenuItem(title: "Move Down", action: #selector(contextMoveDown(_:)), keyEquivalent: "")
                downItem.target = self
                downItem.representedObject = clickedRow
                menu.addItem(downItem)
            }

            menu.addItem(NSMenuItem.separator())

            // Show in Finder
            let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(contextShowInFinder(_:)), keyEquivalent: "")
            finderItem.target = self
            finderItem.representedObject = track
            menu.addItem(finderItem)
        }

        @objc func contextPlayNow(_ sender: NSMenuItem) {
            guard let index = sender.representedObject as? Int else { return }
            parent.onPlayTrack?(index)
        }

        @objc func contextMoveUp(_ sender: NSMenuItem) {
            guard let index = sender.representedObject as? Int, index > 0 else { return }
            parent.onReorder?(index, index - 1)
        }

        @objc func contextMoveDown(_ sender: NSMenuItem) {
            guard let index = sender.representedObject as? Int, index < parent.tracks.count - 1 else { return }
            parent.onReorder?(index, index + 1)
        }

        @objc func contextToggleFavorite(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            PlayerManager.shared.toggleFavorite(track: track)
        }

        @objc func contextCreatePlaylistAndAdd(_ sender: NSMenuItem) {
            guard let tracks = sender.representedObject as? [Track] else { return }
            PlaylistMenuHelper.shared.showCreatePlaylistDialog(tracks: tracks)
        }

        @objc func contextAddToPlaylist(_ sender: NSMenuItem) {
            guard let (trackId, playlistId) = sender.representedObject as? (Int64, Int64) else { return }
            PlaylistDAO().addTrack(playlistId: playlistId, trackId: trackId)
            NotificationCenter.default.post(
                name: Constants.Notifications.playlistContentChanged,
                object: nil,
                userInfo: ["playlistId": playlistId]
            )
        }

        @objc func contextRemoveFromQueue(_ sender: NSMenuItem) {
            guard let index = sender.representedObject as? Int else { return }
            parent.onRemove?(index)
        }

        @objc func contextShowInFinder(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            let url = URL(fileURLWithPath: track.filePath)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

// MARK: - QueueCellView

class QueueCellView: NSView {
    private let artworkImageView = NSImageView()
    private let indexLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private var isSetUp = false
    private var currentAlbumKey: String?

    func configure(track: Track, index: Int, isCurrent: Bool) {
        if !isSetUp {
            setUp()
        }

        indexLabel.stringValue = isCurrent ? "\u{25B6}" : "\(index + 1)"
        titleLabel.stringValue = track.title

        var subtitle = track.displayArtist
        if let album = track.albumTitle, !album.isEmpty {
            subtitle += " \u{2022} \(album)"
        }
        subtitleLabel.stringValue = subtitle
        durationLabel.stringValue = track.formattedDuration

        let accentColor = NSColor.controlAccentColor
        indexLabel.textColor = isCurrent ? accentColor : .secondaryLabelColor
        titleLabel.textColor = isCurrent ? accentColor : .labelColor

        // Load artwork by album (uses cache, avoids per-file I/O)
        let albumKey = "\(track.albumTitle ?? "")-\(track.albumArtistName ?? track.artistName ?? "")"
        if currentAlbumKey != albumKey {
            currentAlbumKey = albumKey

            // Set placeholder immediately
            let placeholderImage = NSImage(systemSymbolName: "music.note", accessibilityDescription: "No artwork")
            artworkImageView.image = placeholderImage
            artworkImageView.contentTintColor = .secondaryLabelColor

            if let albumTitle = track.albumTitle, !albumTitle.isEmpty {
                ArtworkManager.shared.fetchAlbumArtwork(albumTitle: albumTitle, artistName: track.albumArtistName ?? track.artistName) { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self = self, self.currentAlbumKey == albumKey else { return }
                        if case .success(let image) = result {
                            self.artworkImageView.image = image
                            self.artworkImageView.contentTintColor = nil
                        }
                    }
                }
            }
        }
    }

    private func setUp() {
        isSetUp = true

        // Artwork image view
        artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        artworkImageView.imageScaling = .scaleProportionallyUpOrDown
        artworkImageView.wantsLayer = true
        artworkImageView.layer?.cornerRadius = 4
        artworkImageView.layer?.masksToBounds = true
        addSubview(artworkImageView)

        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        indexLabel.font = .systemFont(ofSize: 12)
        indexLabel.alignment = .center
        indexLabel.lineBreakMode = .byClipping
        addSubview(indexLabel)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(subtitleLabel)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.textColor = .secondaryLabelColor
        durationLabel.alignment = .right
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(durationLabel)

        NSLayoutConstraint.activate([
            // Artwork: 32x32, left side
            artworkImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            artworkImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            artworkImageView.widthAnchor.constraint(equalToConstant: 32),
            artworkImageView.heightAnchor.constraint(equalToConstant: 32),

            // Index label after artwork
            indexLabel.leadingAnchor.constraint(equalTo: artworkImageView.trailingAnchor, constant: 4),
            indexLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            indexLabel.widthAnchor.constraint(equalToConstant: 26),

            // Title and subtitle after index
            titleLabel.leadingAnchor.constraint(equalTo: indexLabel.trailingAnchor, constant: 4),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: durationLabel.leadingAnchor, constant: -8),

            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
