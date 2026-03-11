import SwiftUI
import AppKit

struct TrackTableConfig {
    var showRemoveFromPlaylist: Bool = false
    var removeFromPlaylistLabel: String = "Remove from Playlist"
    var onRemoveFromPlaylist: (([Int64]) -> Void)? = nil
    var onEditTrack: ((Track) -> Void)? = nil
    var allowReorder: Bool = false
    var onReorder: (([Int64]) -> Void)? = nil
}

struct TrackTableView: NSViewRepresentable {
    let tracks: [Track]
    var config: TrackTableConfig = TrackTableConfig()
    var onPlayTrack: ((Track, [Track]) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let tableView = NSTableView()
        tableView.style = .inset
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.intercellSpacing = NSSize(width: 10, height: 4)
        tableView.rowHeight = 24

        let columns: [(String, String, CGFloat, CGFloat)] = [
            ("trackNumber", "#", 35, 35),
            ("title", "Title", 200, 10000),
            ("artist", "Artist", 150, 10000),
            ("album", "Album", 150, 10000),
            ("year", "Year", 50, 60),
            ("duration", "Duration", 65, 80),
        ]

        for (id, title, minWidth, maxWidth) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.minWidth = minWidth
            col.maxWidth = maxWidth
            col.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            if id == "trackNumber" || id == "year" || id == "duration" {
                col.headerCell.alignment = .right
            }
            tableView.addTableColumn(col)
        }

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.doubleAction = #selector(Coordinator.doubleClickRow(_:))
        tableView.target = context.coordinator

        // Drag support
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.registerForDraggedTypes([TrackDragHelper.pasteboardType, .string])

        if config.allowReorder {
            tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        }

        // Context menu
        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.tracks = tracks

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.config = config
        context.coordinator.tracks = tracks
        context.coordinator.tableView?.reloadData()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        var parent: TrackTableView
        var config: TrackTableConfig
        var tracks: [Track] = []
        var cachedPlaylists: [Playlist]?
        private var playlistCacheTime: Date = .distantPast
        weak var tableView: NSTableView?

        init(_ parent: TrackTableView) {
            self.parent = parent
            self.config = parent.config
            super.init()
        }

        // MARK: DataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            tracks.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < tracks.count, let columnID = tableColumn?.identifier.rawValue else { return nil }
            let track = tracks[row]

            // Title column uses a custom view with optional Hi-Res badge
            if columnID == "title" {
                let cellID = NSUserInterfaceItemIdentifier("TrackTitleCell")
                let container: NSStackView
                let titleLabel: NSTextField
                let badge: NSTextField

                if let existing = tableView.makeView(withIdentifier: cellID, owner: self) as? NSStackView,
                   existing.arrangedSubviews.count >= 2,
                   let existingTitle = existing.arrangedSubviews[0] as? NSTextField,
                   let existingBadge = existing.arrangedSubviews[1] as? NSTextField {
                    container = existing
                    titleLabel = existingTitle
                    badge = existingBadge
                } else {
                    titleLabel = NSTextField(labelWithString: "")
                    titleLabel.lineBreakMode = .byTruncatingTail
                    titleLabel.font = .systemFont(ofSize: 13)
                    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                    badge = NSTextField(labelWithString: "")
                    badge.font = .systemFont(ofSize: 9, weight: .bold)
                    badge.textColor = .orange
                    badge.backgroundColor = NSColor.orange.withAlphaComponent(0.15)
                    badge.drawsBackground = true
                    badge.isBordered = false
                    badge.isEditable = false
                    badge.wantsLayer = true
                    badge.layer?.cornerRadius = 3
                    badge.setContentCompressionResistancePriority(.required, for: .horizontal)
                    badge.setContentHuggingPriority(.required, for: .horizontal)

                    container = NSStackView(views: [titleLabel, badge])
                    container.identifier = cellID
                    container.orientation = .horizontal
                    container.spacing = 6
                    container.alignment = .centerY
                }

                titleLabel.stringValue = track.title

                let isHiRes = (track.bitDepth ?? 0) > 16 || (track.sampleRate ?? 0) > 44100
                if isHiRes {
                    badge.isHidden = false
                    badge.stringValue = " Hi-Res "
                } else {
                    badge.isHidden = true
                    badge.stringValue = ""
                }

                return container
            }

            let cellID = NSUserInterfaceItemIdentifier("TrackCell_\(columnID)")
            let textField: NSTextField
            if let existing = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTextField {
                textField = existing
            } else {
                textField = NSTextField(labelWithString: "")
                textField.identifier = cellID
                textField.lineBreakMode = .byTruncatingTail
                textField.font = .systemFont(ofSize: 13)
            }

            switch columnID {
            case "trackNumber":
                textField.stringValue = track.trackNumber.map { String($0) } ?? ""
                textField.alignment = .right
            case "artist":
                textField.stringValue = track.displayArtist
            case "album":
                textField.stringValue = track.displayAlbum
            case "year":
                textField.stringValue = track.year.map { String($0) } ?? ""
                textField.alignment = .right
            case "duration":
                textField.stringValue = track.formattedDuration
                textField.alignment = .right
            default:
                break
            }

            return textField
        }

        // MARK: Double-click

        @objc func doubleClickRow(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < tracks.count else { return }
            parent.onPlayTrack?(tracks[row], tracks)
        }

        // MARK: Sorting

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            let sortDescriptors = tableView.sortDescriptors
            guard let descriptor = sortDescriptors.first, let key = descriptor.key else { return }
            let ascending = descriptor.ascending

            tracks.sort { a, b in
                let result: ComparisonResult
                switch key {
                case "trackNumber":
                    let aNum = a.trackNumber ?? 0
                    let bNum = b.trackNumber ?? 0
                    result = aNum < bNum ? .orderedAscending : (aNum > bNum ? .orderedDescending : .orderedSame)
                case "title":
                    result = a.title.localizedStandardCompare(b.title)
                case "artist":
                    result = a.displayArtist.localizedStandardCompare(b.displayArtist)
                case "album":
                    result = a.displayAlbum.localizedStandardCompare(b.displayAlbum)
                case "year":
                    let aYear = a.year ?? 0
                    let bYear = b.year ?? 0
                    result = aYear < bYear ? .orderedAscending : (aYear > bYear ? .orderedDescending : .orderedSame)
                case "duration":
                    result = a.duration < b.duration ? .orderedAscending : (a.duration > b.duration ? .orderedDescending : .orderedSame)
                default:
                    result = .orderedSame
                }
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }

            tableView.reloadData()
        }

        // MARK: Drag Source

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard row < tracks.count else { return nil }

            let selectedRows = tableView.selectedRowIndexes
            let dragRows: IndexSet
            if selectedRows.contains(row) {
                dragRows = selectedRows
            } else {
                dragRows = IndexSet(integer: row)
            }

            let trackIDs = dragRows.compactMap { idx -> Int64? in
                guard idx < tracks.count else { return nil }
                return tracks[idx].id
            }

            let item = NSPasteboardItem()
            let encoded = TrackDragHelper.encode(trackIDs)
            item.setString(encoded, forType: TrackDragHelper.pasteboardType)
            item.setString(encoded, forType: .string)
            return item
        }

        // MARK: Drop (Reorder)

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            guard config.allowReorder else { return [] }
            if dropOperation == .above {
                return .move
            }
            return []
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            guard config.allowReorder else { return false }
            guard let pasteboardData = info.draggingPasteboard.string(forType: TrackDragHelper.pasteboardType) else { return false }

            guard let draggedIDs = TrackDragHelper.decode(pasteboardData) else { return false }

            // Build new order
            var newTracks = tracks.filter { !draggedIDs.contains($0.id) }
            let movedTracks = tracks.filter { draggedIDs.contains($0.id) }

            // Adjust insertion index after removing dragged items
            let insertAt = min(row, newTracks.count)
            newTracks.insert(contentsOf: movedTracks, at: insertAt)

            tracks = newTracks
            tableView.reloadData()

            let reorderedIDs: [Int64] = newTracks.map { $0.id }
            config.onReorder?(reorderedIDs)
            return true
        }

        // MARK: Context Menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView = tableView else { return }

            let clickedRow = tableView.clickedRow
            guard clickedRow >= 0, clickedRow < tracks.count else { return }

            let selectedRows = tableView.selectedRowIndexes
            let relevantRows: IndexSet
            if selectedRows.contains(clickedRow) {
                relevantRows = selectedRows
            } else {
                relevantRows = IndexSet(integer: clickedRow)
            }

            let selectedTracks = relevantRows.compactMap { idx -> Track? in
                guard idx < tracks.count else { return nil }
                return tracks[idx]
            }

            let selectedIDs = selectedTracks.map(\.id)

            // Play Now
            let playItem = NSMenuItem(title: "Play Now", action: #selector(contextPlayNow(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = selectedTracks
            menu.addItem(playItem)

            // Add to Queue
            let queueItem = NSMenuItem(title: "Add to Queue", action: #selector(contextAddToQueue(_:)), keyEquivalent: "")
            queueItem.target = self
            queueItem.representedObject = selectedTracks
            menu.addItem(queueItem)

            // Play Next
            let nextItem = NSMenuItem(title: "Play Next", action: #selector(contextPlayNext(_:)), keyEquivalent: "")
            nextItem.target = self
            nextItem.representedObject = selectedTracks
            menu.addItem(nextItem)

            menu.addItem(NSMenuItem.separator())

            // Favorites toggle
            let isFav = selectedTracks.count == 1 && selectedTracks[0].isFavorite
            let favTitle = isFav ? "Remove from Favorites" : "Add to Favorites"
            let favItem = NSMenuItem(title: favTitle, action: #selector(contextToggleFavorite(_:)), keyEquivalent: "")
            favItem.target = self
            favItem.representedObject = selectedTracks
            menu.addItem(favItem)

            // Add to Playlist submenu
            let playlistSubmenu = NSMenu()
            let createItem = NSMenuItem(title: "Create New Playlist...", action: #selector(contextCreatePlaylistAndAdd(_:)), keyEquivalent: "")
            createItem.target = self
            createItem.representedObject = selectedTracks
            playlistSubmenu.addItem(createItem)
            if cachedPlaylists == nil || Date().timeIntervalSince(playlistCacheTime) > 5 {
                cachedPlaylists = PlaylistDAO().getAll()
                playlistCacheTime = Date()
            }
            let playlists = cachedPlaylists ?? []
            if !playlists.isEmpty {
                playlistSubmenu.addItem(NSMenuItem.separator())
                for playlist in playlists {
                    let pItem = NSMenuItem(title: playlist.name, action: #selector(contextAddToPlaylist(_:)), keyEquivalent: "")
                    pItem.target = self
                    pItem.representedObject = (selectedIDs, playlist.id)
                    playlistSubmenu.addItem(pItem)
                }
            }
            let playlistMenuItem = NSMenuItem(title: "Add to Playlist", action: nil, keyEquivalent: "")
            playlistMenuItem.submenu = playlistSubmenu
            menu.addItem(playlistMenuItem)

            // Remove from Playlist
            if config.showRemoveFromPlaylist {
                let removeItem = NSMenuItem(title: config.removeFromPlaylistLabel, action: #selector(contextRemoveFromPlaylist(_:)), keyEquivalent: "")
                removeItem.target = self
                removeItem.representedObject = selectedIDs
                menu.addItem(removeItem)
            }

            menu.addItem(NSMenuItem.separator())

            // Edit Info (single track only)
            if selectedTracks.count == 1 {
                let editItem = NSMenuItem(title: "Edit Info", action: #selector(contextEditInfo(_:)), keyEquivalent: "")
                editItem.target = self
                editItem.representedObject = selectedTracks.first
                menu.addItem(editItem)
            }

            // Show in Finder
            let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(contextShowInFinder(_:)), keyEquivalent: "")
            finderItem.target = self
            finderItem.representedObject = selectedTracks
            menu.addItem(finderItem)
        }

        @objc func contextPlayNow(_ sender: NSMenuItem) {
            guard let selectedTracks = sender.representedObject as? [Track],
                  let first = selectedTracks.first else { return }
            parent.onPlayTrack?(first, tracks)
        }

        @objc func contextAddToQueue(_ sender: NSMenuItem) {
            guard let selectedTracks = sender.representedObject as? [Track] else { return }
            QueueManager.shared.addToQueue(selectedTracks)
        }

        @objc func contextPlayNext(_ sender: NSMenuItem) {
            guard let selectedTracks = sender.representedObject as? [Track] else { return }
            QueueManager.shared.insertNext(selectedTracks)
        }

        @objc func contextToggleFavorite(_ sender: NSMenuItem) {
            guard let selectedTracks = sender.representedObject as? [Track] else { return }
            for track in selectedTracks {
                PlayerManager.shared.toggleFavorite(track: track)
            }
        }

        @objc func contextCreatePlaylistAndAdd(_ sender: NSMenuItem) {
            guard let tracks = sender.representedObject as? [Track] else { return }
            PlaylistMenuHelper.shared.showCreatePlaylistDialog(tracks: tracks)
        }

        @objc func contextAddToPlaylist(_ sender: NSMenuItem) {
            guard let (trackIDs, playlistId) = sender.representedObject as? ([Int64], Int64) else { return }
            let dao = PlaylistDAO()
            for trackId in trackIDs {
                dao.addTrack(playlistId: playlistId, trackId: trackId)
            }
            NotificationCenter.default.post(
                name: Constants.Notifications.playlistContentChanged,
                object: nil,
                userInfo: ["playlistId": playlistId]
            )
        }

        @objc func contextRemoveFromPlaylist(_ sender: NSMenuItem) {
            guard let trackIDs = sender.representedObject as? [Int64] else { return }
            config.onRemoveFromPlaylist?(trackIDs)
        }

        @objc func contextEditInfo(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            config.onEditTrack?(track)
        }

        @objc func contextShowInFinder(_ sender: NSMenuItem) {
            guard let selectedTracks = sender.representedObject as? [Track] else { return }
            let urls = selectedTracks.compactMap { URL(fileURLWithPath: $0.filePath) }
            if !urls.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
        }
    }
}
