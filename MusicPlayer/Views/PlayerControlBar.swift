import SwiftUI

struct PlayerControlBar: View {
    @ObservedObject var nowPlaying = NowPlayingManager.shared
    @Binding var showQueue: Bool

    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0
    @State private var isMuted = false
    @State private var previousVolume: Float = 0.8

    var body: some View {
        VStack(spacing: 4) {
            // Controls - all sections vertically centered
            HStack(alignment: .center, spacing: 16) {
                // Track info (left side)
                HStack(spacing: 10) {
                    // Artwork thumbnail (reduced size)
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
                                .padding(10)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(5)
                    .accessibilityLabel("Album artwork")

                    // Track details
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlaying.currentTrack?.title ?? "No track playing")
                            .font(.body)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Text(nowPlaying.currentTrack?.displayArtist ?? "Unknown Artist")
                            .font(.subheadline)
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
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(nowPlaying.currentTrack == nil)
                    .help(nowPlaying.currentTrack?.isFavorite == true ? "Remove from Favorites" : "Add to Favorites")
                }
                .frame(minWidth: 300, idealWidth: 320, alignment: .leading)

                Spacer()

                // Playback controls (center) - vertically centered
                HStack(spacing: 18) {
                    // Previous
                    Button(action: {
                        nowPlaying.previous()
                    }) {
                        Image(systemName: Icons.previousFIll)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(nowPlaying.currentTrack == nil)
                    .help("Previous Track")
                    .accessibilityLabel("Previous track")

                    // Play/Pause
                    Button(action: {
                        nowPlaying.togglePlayPause()
                    }) {
                        Image(systemName: nowPlaying.playbackState == .playing ? Icons.pauseCircleFill : Icons.playCircleFill)
                            .font(.system(size: 32))
                    }
                    .buttonStyle(.plain)
                    .disabled(nowPlaying.currentTrack == nil)
                    .help(nowPlaying.playbackState == .playing ? "Pause" : "Play")
                    .accessibilityLabel(nowPlaying.playbackState == .playing ? "Pause" : "Play")

                    // Next
                    Button(action: {
                        nowPlaying.next()
                    }) {
                        Image(systemName: Icons.nextFill)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(nowPlaying.currentTrack == nil)
                    .help("Next Track")
                    .accessibilityLabel("Next track")
                }

                Spacer()

                // Volume and queue controls (right side) - vertically centered
                HStack(spacing: 16) {
                    // Shuffle
                    Button(action: {
                        nowPlaying.toggleShuffle()
                    }) {
                        ZStack {
                            if nowPlaying.isShuffleEnabled {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 28, height: 28)
                            }
                            Image(systemName: Icons.shuffleFill)
                                .foregroundColor(nowPlaying.isShuffleEnabled ? .blue : .secondary)
                                .font(.system(size: 17, weight: nowPlaying.isShuffleEnabled ? .semibold : .regular))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(nowPlaying.isShuffleEnabled ? "Shuffle: On" : "Shuffle: Off")
                    .accessibilityLabel(nowPlaying.isShuffleEnabled ? "Shuffle on" : "Shuffle off")

                    // Repeat
                    Button(action: {
                        nowPlaying.cycleRepeatMode()
                    }) {
                        ZStack {
                            if nowPlaying.repeatMode != .off {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 28, height: 28)
                            }
                            Image(systemName: nowPlaying.repeatMode == .one ? Icons.repeat1Fill : Icons.repeatFill)
                                .foregroundColor(nowPlaying.repeatMode == .off ? .secondary : .blue)
                                .font(.system(size: 17, weight: nowPlaying.repeatMode != .off ? .semibold : .regular))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(nowPlaying.repeatMode == .off ? "Repeat: Off" :
                          nowPlaying.repeatMode == .one ? "Repeat: One" : "Repeat: All")
                    .accessibilityLabel(nowPlaying.repeatMode == .off ? "Repeat off" :
                          nowPlaying.repeatMode == .one ? "Repeat one" : "Repeat all")

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
                            Image(systemName: isMuted || nowPlaying.volume == 0 ? "speaker.slash.fill" :
                                  nowPlaying.volume < 0.33 ? "speaker.wave.1.fill" :
                                  nowPlaying.volume < 0.66 ? "speaker.wave.2.fill" : Icons.speakerWave3Fill)
                                .foregroundStyle(.secondary)
                                .font(.system(size: 15))
                        }
                        .buttonStyle(.plain)
                        .help(isMuted ? "Unmute" : "Mute")

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
                        .help("Volume: \(Int(nowPlaying.volume * 100))%")
                        .accessibilityLabel("Volume slider")
                        .accessibilityValue("\(Int(nowPlaying.volume * 100)) percent")
                    }

                    // Queue toggle button
                    Button(action: {
                        withAnimation {
                            showQueue.toggle()
                        }
                    }) {
                        Image(systemName: Icons.musicNoteList)
                            .foregroundColor(showQueue ? .blue : .secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help(showQueue ? "Hide Queue" : "Show Queue")
                    .accessibilityLabel(showQueue ? "Hide queue" : "Show queue")
                }
                .frame(minWidth: 300, idealWidth: 320, alignment: .trailing)
            }
            .padding(.horizontal, 20)

            // Seek bar with inline time labels (compact)
            HStack(spacing: 8) {
                // Current time (left)
                Text((isSeeking ? seekPosition : nowPlaying.currentTime).formattedDuration)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)

                // Seek bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // The actual slider (for dragging)
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
                        .controlSize(.mini)
                        .accessibilityLabel("Seek bar")
                        .accessibilityValue("\(Int(nowPlaying.currentTime)) seconds of \(Int(nowPlaying.duration)) seconds")

                        // Transparent overlay to capture tap gestures
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                // Calculate the position as a percentage of the slider width
                                let sliderWidth = geometry.size.width
                                let percentage = location.x / sliderWidth
                                let clampedPercentage = min(max(0, percentage), 1)

                                // Calculate the time to seek to
                                let duration = max(nowPlaying.duration, 0.01)
                                let targetTime = clampedPercentage * duration

                                // Seek to the calculated position
                                nowPlaying.seek(to: targetTime)
                            }
                    }
                }
                .frame(height: 16)
                .id(nowPlaying.currentTrack?.id ?? -1) // Force recreation when track changes

                // Total duration (right)
                Text(nowPlaying.duration.formattedDuration)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 800)

        }
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .frame(height: 80)
    }
}


