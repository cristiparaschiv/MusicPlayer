import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @State private var artwork: NSImage?
    private let artworkManager = ArtworkManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                Group {
                    if let artwork = artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Color.secondary.opacity(0.2)
                            
                            Image(systemName: Icons.opticalDiscFill)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.secondary.opacity(0.5))
                                .padding(30)
                        }
                    }
                }
                .frame(width: 120, height: 120)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                
                VStack (alignment: .leading, spacing: 12) {
                    Text("Album")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                    
                    Text(album.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .lineLimit(2)
                    
                    HStack {
                        let albumYear = String(album.year ?? 0)
                        Text(albumYear)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("\(album.trackCount) \(album.trackCount == 1 ? "song" : "songs")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("\(album.formattedDuration)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 10) {
                        Button(action: { playAlbum() }) {
                            Image(systemName: Icons.playFill)
                                .font(.system(size: 12))
                            Text("Play")
                                .font(.system(size: 13))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(6)
                }
                
                Spacer()
            }
            .background(.regularMaterial)
            .padding(10)
            
            AlbumSongsView(album: album)
        }
        .onAppear() {
            loadArtwork()
        }
    }
    
    private func loadArtwork() {
        artworkManager.fetchAlbumArtwork(for: album) { result in
            if case .success(let image) = result {
                DispatchQueue.main.async {
                    artwork = image
                }
            }
        }
    }
    
    private func playAlbum() {
        let trackDAO = TrackDAO()
        let tracks = trackDAO.getByAlbumId(albumId: album.id)

        guard !tracks.isEmpty else { return }

        QueueManager.shared.setQueue(tracks, startIndex: 0)
        PlayerManager.shared.play(track: tracks[0])
    }
}


