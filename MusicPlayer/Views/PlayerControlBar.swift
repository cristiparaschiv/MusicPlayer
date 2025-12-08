import SwiftUI

struct PlayerControlBar: View {
    @ObservedObject var nowPlaying = NowPlayingManager.shared
    @Binding var showQueue: Bool

    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0
    @State private var isMuted = false
    @State private var previousVolume: Float = 0.8

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack(spacing: 10) {
                // Track info (left side)
                HStack(spacing: 12) {
                    // Artwork thumbnail
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
                                .padding(8)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)

                    // Track details
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlaying.currentTrack?.title ?? "No track playing")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        Text(nowPlaying.currentTrack?.displayArtist ?? "Unknown Artist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 200, alignment: .leading)

                    // Favorite button
                    Button(action: {
                        nowPlaying.toggleFavorite()
                    }) {
                        Image(systemName: nowPlaying.currentTrack?.isFavorite == true ? Icons.starFill : Icons.star)
                            .foregroundColor(nowPlaying.currentTrack?.isFavorite == true ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(nowPlaying.currentTrack == nil)
                }
                .frame(width: 300, alignment: .leading)

                Spacer()

                // Playback controls (center)
                HStack(spacing: 16) {
                    // Previous
                    Button(action: {
                        nowPlaying.previous()
                    }) {
                        Image(systemName: Icons.previousFIll)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(nowPlaying.currentTrack == nil)

                    // Play/Pause
                    Button(action: {
                        nowPlaying.togglePlayPause()
                    }) {
                        Image(systemName: nowPlaying.playbackState == .playing ? Icons.pauseCircleFill : Icons.playCircleFill)
                            .font(.system(size: 36))
                    }
                    .buttonStyle(.plain)
                    .disabled(nowPlaying.currentTrack == nil)

                    // Next
                    Button(action: {
                        nowPlaying.next()
                    }) {
                        Image(systemName: Icons.nextFill)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(nowPlaying.currentTrack == nil)
                }

                Spacer()

                // Volume and queue controls (right side)
                HStack(spacing: 16) {
                    // Shuffle
                    Button(action: {
                        nowPlaying.toggleShuffle()
                    }) {
                        Image(systemName: Icons.shuffleFill)
                            .foregroundColor(nowPlaying.isShuffleEnabled ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)

                    // Repeat
                    Button(action: {
                        nowPlaying.cycleRepeatMode()
                    }) {
                        Image(systemName: nowPlaying.repeatMode == .one ? Icons.repeat1Fill : Icons.repeatFill)
                            .foregroundColor(nowPlaying.repeatMode == .off ? .secondary : .blue)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(height: 20)

                    // Volume control
                    HStack(spacing: 8) {
                        Button(action: {
                            if isMuted {
                                isMuted = false
                                nowPlaying.setVolume(previousVolume)
                            } else {
                                isMuted = true
                                previousVolume = nowPlaying.volume
                                nowPlaying.setVolume(0)
                            }
                        }) {
                            Image(systemName: isMuted || nowPlaying.volume == 0 ? "speaker.slash.fill" : Icons.speakerWave3Fill)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Slider(value: Binding(
                            get: { Double(nowPlaying.volume) },
                            set: { newValue in
                                let volume = Float(newValue)
                                nowPlaying.setVolume(volume)
                                if volume > 0 {
                                    isMuted = false
                                }
                            }
                        ), in: 0...1)
                        .frame(width: 100)
                        .controlSize(.small)
                    }

                    // Queue toggle button
                    Button(action: {
                        withAnimation {
                            showQueue.toggle()
                        }
                    }) {
                        Image(systemName: Icons.musicNoteList)
                            .foregroundColor(showQueue ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 300, alignment: .trailing)
            }
            .padding(.horizontal)
            //.padding(.top, 8)
            .padding(.bottom, 12)

            // Seek bar
            VStack(spacing: 4) {
                Slider(
                    value: isSeeking ? $seekPosition : Binding(
                        get: { nowPlaying.currentTime },
                        set: { _ in }
                    ),
                    in: 0...max(nowPlaying.duration, 0.01),
                    onEditingChanged: { editing in
                        if editing {
                            isSeeking = true
                            seekPosition = nowPlaying.currentTime
                        } else {
                            isSeeking = false
                            nowPlaying.seek(to: seekPosition)
                        }
                    }
                )
                .controlSize(.small)

                HStack {
                    Text(nowPlaying.currentTime.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer()

                    Text(nowPlaying.duration.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .frame(height: 10)
            .frame(maxWidth: 800)
            
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}


