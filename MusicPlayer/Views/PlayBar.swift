import SwiftUI

struct PlayerBar: View {
    var body: some View {
        HStack {
            // Song info
            HStack {
                Rectangle().fill(Color.gray).frame(width: 40, height: 40).cornerRadius(6)
                VStack(alignment: .leading) {
                    Text("start a war")
                    Text("JENNIE — Ruby").font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()
            
            // Player controls
            HStack(spacing: 20) {
                Button(action: {}) {
                    Image(systemName: "backward.fill")
                }

                Button(action: {}) {
                    Image(systemName: "play.fill")
                }

                Button(action: {}) {
                    Image(systemName: "forward.fill")
                }
            }

            Spacer()

            Slider(value: .constant(0.4))
                .frame(width: 200)
        }
        .padding()
        .background(Material.bar)
    }
}
