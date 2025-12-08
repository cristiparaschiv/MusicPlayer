import SwiftUI

struct ArtistsView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Artists")
                .font(.largeTitle)
                .bold()
                .padding()

            ScrollView {
                ArtistGrid()
                    .padding()
            }
        }
    }
}
