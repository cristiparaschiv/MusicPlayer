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

                    Text("You can select multiple folders at once")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .multilineTextAlignment(.center)
            }

            // Add button
            Button(action: {
                MediaScannerManager.shared.addFolder()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: Icons.plusCircleFill)
                        .font(.system(size: 16))
                    Text("Add Music Folder")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .transition(.opacity)
    }
}
