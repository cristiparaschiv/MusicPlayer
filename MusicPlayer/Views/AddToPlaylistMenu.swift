import SwiftUI
import AppKit

// Helper class to manage playlist operations
class PlaylistMenuHelper {
    static let shared = PlaylistMenuHelper()
    private let playlistDAO = PlaylistDAO()

    private init() {}

    func addToPlaylist(_ playlist: Playlist, tracks: [Track]) {
        for track in tracks {
            playlistDAO.addTrack(playlistId: playlist.id, trackId: track.id)
        }

        NotificationCenter.default.post(
            name: Constants.Notifications.playlistContentChanged,
            object: nil,
            userInfo: ["playlistId": playlist.id]
        )
    }

    func createPlaylistAndAdd(name: String, tracks: [Track]) {
        let newPlaylist = Playlist(id: 0, name: name)
        let playlistId = playlistDAO.insert(playlist: newPlaylist)

        // Add tracks to the new playlist
        for track in tracks {
            playlistDAO.addTrack(playlistId: playlistId, trackId: track.id)
        }

        NotificationCenter.default.post(name: Constants.Notifications.playlistsChanged, object: nil)
        NotificationCenter.default.post(
            name: Constants.Notifications.playlistContentChanged,
            object: nil,
            userInfo: ["playlistId": playlistId]
        )
    }

    func showCreatePlaylistDialog(tracks: [Track]) {
        let alert = NSAlert()
        alert.messageText = "New Playlist"
        alert.informativeText = "Enter a name for your new playlist"
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "Playlist name"
        alert.accessoryView = textField

        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let name = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                createPlaylistAndAdd(name: name, tracks: tracks)
            }
        }
    }
}

struct AddToPlaylistMenu: View {
    let tracks: [Track]

    private var playlists: [Playlist] {
        PlaylistDAO().getAll()
    }

    var body: some View {
        Menu("Add to Playlist") {
            Button("Create New Playlist...") {
                PlaylistMenuHelper.shared.showCreatePlaylistDialog(tracks: tracks)
            }

            if !playlists.isEmpty {
                Divider()

                ForEach(playlists, id: \.id) { playlist in
                    Button(playlist.name) {
                        PlaylistMenuHelper.shared.addToPlaylist(playlist, tracks: tracks)
                    }
                }
            }
        }
    }
}
