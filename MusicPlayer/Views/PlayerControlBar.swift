import SwiftUI

struct PlayerControlBar: View {
    @ObservedObject var nowPlaying = NowPlayingManager.shared
    @ObservedObject var progress = PlaybackProgressManager.shared
    @Binding var showQueue: Bool
    @Binding var showNowPlaying: Bool

    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0
    @State private var isMuted = false
    @State private var previousVolume: Float = 0.8

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // MARK: - Left: Artwork + Track Info + Favorite
            HStack(spacing: 10) {
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
                            .padding(10)
                    }
                }
                .frame(width: 48, height: 48)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(5)
                .animation(.easeInOut(duration: 0.4), value: nowPlaying.currentTrack?.id)
                .accessibilityLabel("Album artwork")

                // Track details
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.currentTrack?.title ?? "No track playing")
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(nowPlaying.currentTrack?.displayArtist ?? "Unknown Artist")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let badge = audioFormatBadge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .cornerRadius(3)
                        }
                    }
                    if RadioManager.shared.isActive, let station = RadioManager.shared.activeStation {
                        HStack(spacing: 4) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.caption2)
                            Text(station.name)
                                .font(.caption2)
                        }
                        .foregroundColor(.accentColor)
                    }
                }
                .frame(minWidth: 120, maxWidth: 200, alignment: .leading)

                // Favorite button
                Button(action: {
                    nowPlaying.toggleFavorite()
                }) {
                    Image(systemName: nowPlaying.currentTrack?.isFavorite == true ? Icons.starFill : Icons.star)
                        .foregroundColor(nowPlaying.currentTrack?.isFavorite == true ? .pink : .secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .disabled(nowPlaying.currentTrack == nil)
                .help(nowPlaying.currentTrack?.isFavorite == true ? "Remove from Favorites" : "Add to Favorites")
            }

            Divider()
                .frame(height: 24)

            // MARK: - Center: Transport Controls + Seek Bar

            // Shuffle
            Button(action: {
                nowPlaying.toggleShuffle()
            }) {
                ZStack {
                    if nowPlaying.isShuffleEnabled {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 24, height: 24)
                    }
                    Image(systemName: Icons.shuffleFill)
                        .foregroundColor(nowPlaying.isShuffleEnabled ? .blue : .secondary)
                        .font(.system(size: 14, weight: nowPlaying.isShuffleEnabled ? .semibold : .regular))
                }
            }
            .buttonStyle(.plain)
            .help(nowPlaying.isShuffleEnabled ? "Shuffle: On" : "Shuffle: Off")
            .accessibilityLabel(nowPlaying.isShuffleEnabled ? "Shuffle on" : "Shuffle off")

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
                    .font(.system(size: 28))
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

            // Repeat
            Button(action: {
                nowPlaying.cycleRepeatMode()
            }) {
                ZStack {
                    if nowPlaying.repeatMode != .off {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 24, height: 24)
                    }
                    Image(systemName: nowPlaying.repeatMode == .one ? Icons.repeat1Fill : Icons.repeatFill)
                        .foregroundColor(nowPlaying.repeatMode == .off ? .secondary : .blue)
                        .font(.system(size: 14, weight: nowPlaying.repeatMode != .off ? .semibold : .regular))
                }
            }
            .buttonStyle(.plain)
            .help(nowPlaying.repeatMode == .off ? "Repeat: Off" :
                  nowPlaying.repeatMode == .one ? "Repeat: One" : "Repeat: All")
            .accessibilityLabel(nowPlaying.repeatMode == .off ? "Repeat off" :
                  nowPlaying.repeatMode == .one ? "Repeat one" : "Repeat all")

            // Seek bar with inline time labels
            HStack(spacing: 6) {
                // Current time
                Text((isSeeking ? seekPosition : progress.currentTime).formattedDuration)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 32, alignment: .trailing)

                // Seek bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Slider(
                            value: isSeeking ? $seekPosition : Binding(
                                get: { progress.currentTime },
                                set: { _ in }
                            ),
                            in: 0...max(progress.duration, 0.01),
                            onEditingChanged: { editing in
                                if editing {
                                    isSeeking = true
                                    seekPosition = progress.currentTime
                                } else {
                                    isSeeking = false
                                    nowPlaying.seek(to: seekPosition)
                                }
                            }
                        )
                        .controlSize(.mini)
                        .accessibilityLabel("Seek bar")
                        .accessibilityValue("\(Int(progress.currentTime)) seconds of \(Int(progress.duration)) seconds")

                        // Transparent overlay for tap-to-seek
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                let sliderWidth = geometry.size.width
                                let percentage = location.x / sliderWidth
                                let clampedPercentage = min(max(0, percentage), 1)
                                let duration = max(progress.duration, 0.01)
                                let targetTime = clampedPercentage * duration
                                nowPlaying.seek(to: targetTime)
                            }
                    }
                }
                .frame(height: 16)
                .id(nowPlaying.currentTrack?.id ?? -1)

                // Total duration
                Text(progress.duration.formattedDuration)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 32, alignment: .leading)
            }

            Divider()
                .frame(height: 24)

            // MARK: - Right: Volume + Queue

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
                        .font(.system(size: 13))
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
                .frame(minWidth: 60, maxWidth: 100)
                .controlSize(.small)
                .help("Volume: \(Int(nowPlaying.volume * 100))%")
                .accessibilityLabel("Volume slider")
                .accessibilityValue("\(Int(nowPlaying.volume * 100)) percent")
            }

            // Now Playing sidebar toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showNowPlaying.toggle()
                    if !showNowPlaying { showQueue = false }
                }
            }) {
                Image(systemName: "sidebar.trailing")
                    .foregroundColor(showNowPlaying ? .blue : .secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help(showNowPlaying ? "Hide Now Playing" : "Show Now Playing")

            // Queue toggle button
            Button(action: {
                withAnimation {
                    showQueue.toggle()
                    if showQueue { showNowPlaying = true }
                }
            }) {
                Image(systemName: Icons.musicNoteList)
                    .foregroundColor(showQueue ? .blue : .secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help(showQueue ? "Hide Queue" : "Show Queue")
            .accessibilityLabel(showQueue ? "Hide queue" : "Show queue")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .frame(height: 60)
    }

    /// Compact format badge like "FLAC 24/96" or "MP3 320"
    private var audioFormatBadge: String? {
        guard let track = nowPlaying.currentTrack else { return nil }

        var parts: [String] = []

        if let format = track.formatName, !format.isEmpty {
            parts.append(format.uppercased())
        }

        if let bitDepth = track.bitDepth, bitDepth > 0,
           let sampleRate = track.sampleRate, sampleRate > 0 {
            let khz = Double(sampleRate) / 1000.0
            let khzStr = khz.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(khz))" : String(format: "%.1f", khz)
            parts.append("\(bitDepth)/\(khzStr)")
        } else if let bitrate = track.bitrate, bitrate > 0 {
            parts.append("\(bitrate)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
