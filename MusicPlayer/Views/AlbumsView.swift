import SwiftUI

struct AlbumsView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Albums")
                .font(.largeTitle)
                .bold()
                .padding()

            ScrollView {
                AlbumGrid()
                    .padding()
            }
        }
    }
}
