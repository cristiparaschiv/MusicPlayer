import SwiftUI

struct EmptyMusicLibraryView: View {
    
    // Customization options
    let context: EmptyStateContext

    enum EmptyStateContext {
        case mainWindow
        case settings

        var iconSize: CGFloat {
            switch self {
            case .mainWindow: return 80
            case .settings: return 60
            }
        }

        var spacing: CGFloat {
            switch self {
            case .mainWindow: return 24
            case .settings: return 20
        }
        }

        var titleFont: Font {
            switch self {
            case .mainWindow: return .largeTitle
            case .settings: return .title2
            }
        }
    }
    
    var body: some View {
        VStack(spacing: context.spacing) {
            // Icon with subtle animation
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: context.iconSize * 1.8, height: context.iconSize * 1.8)

                Image(systemName: Icons.folderBadgePlus)
                    .font(.system(size: context.iconSize, weight: .light))
                    .foregroundColor(.accentColor)
                    .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.5))
            }

            VStack(spacing: 12) {
                Text("No Music Added Yet")
                    .font(context.titleFont)
                    .fontWeight(.semibold)

                VStack(spacing: 8) {
                    Text("Add folders containing your music to get started")
                        .font(.title3)
                        .foregroundColor(.secondary)

                    Text("You can also drag and drop folders into the window")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))

                    Text("Supported formats: FLAC, ALAC, WAV, AIFF, MP3, AAC, OGG, WMA, DSD")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.top, 4)
                }
                .multilineTextAlignment(.center)
            }

            // Add button
            Button(action: {
                MediaScannerManager.shared.addFolder()
            }) {
                Label("Add Music Folder", systemImage: Icons.plusCircleFill)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .transition(.opacity)
    }
}
