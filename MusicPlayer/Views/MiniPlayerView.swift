import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var nowPlaying = NowPlayingManager.shared
    @ObservedObject var playbackProgress = PlaybackProgressManager.shared

    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            // Seek bar at very top — thin, expands on hover
            seekBar
                .frame(height: isHovering ? 8 : 4)
                .animation(.easeInOut(duration: 0.15), value: isHovering)

            // Main content
            HStack(spacing: 12) {
                // Artwork
                Group {
                    if let artwork = nowPlaying.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: Icons.musicNote)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
                .frame(width: 56, height: 56)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.currentTrack?.title ?? "Not Playing")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Text(nowPlaying.currentTrack?.displayArtist ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Transport controls
                HStack(spacing: 12) {
                    Button(action: { nowPlaying.previous() }) {
                        Image(systemName: Icons.previousFIll)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(nowPlaying.currentTrack == nil)

                    Button(action: { nowPlaying.togglePlayPause() }) {
                        Image(systemName: nowPlaying.playbackState == .playing ? Icons.pauseFill : Icons.playFill)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(nowPlaying.currentTrack == nil)

                    Button(action: { nowPlaying.next() }) {
                        Image(systemName: Icons.nextFill)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(nowPlaying.currentTrack == nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 300, height: 76)
        .background(.ultraThinMaterial)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Seek Bar

    private var seekBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))

                // Progress
                let progress = playbackProgress.duration > 0
                    ? (isSeeking ? seekPosition : playbackProgress.currentTime) / playbackProgress.duration
                    : 0
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * CGFloat(min(max(progress, 0), 1)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isSeeking = true
                        let fraction = min(max(value.location.x / geometry.size.width, 0), 1)
                        seekPosition = Double(fraction) * playbackProgress.duration
                    }
                    .onEnded { value in
                        let fraction = min(max(value.location.x / geometry.size.width, 0), 1)
                        let target = Double(fraction) * playbackProgress.duration
                        nowPlaying.seek(to: target)
                        isSeeking = false
                    }
            )
        }
    }
}
