import SwiftUI

struct HomeView: View {
    
    let albumDAO = AlbumDAO()
    @State private var recentAlbums: [Album] = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Shuffle Buttons
                HStack {
                    Button("Shuffle all") { }
                        .buttonStyle(.bordered)
                    Button("Shuffle favorites") { }
                        .buttonStyle(.bordered)
                }

                // Example Sections
                SectionHeader("New Albums")
                AlbumGrid(albums: recentAlbums)

                SectionHeader("Recently Played")
                AlbumGrid(albums: recentAlbums)

                SectionHeader("Frequently Played")
                AlbumGrid(albums: recentAlbums)
            }
            .padding()
        }
        .onAppear {
            loadRecentAlbums()
        }
    }
    
    func loadRecentAlbums() {
        
        recentAlbums = albumDAO.getRecentlyAdded(limit: 5)
    }
}

struct SectionHeader: View {
    var title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.title2)
            .bold()
            .padding(.horizontal, 4)
    }
}
