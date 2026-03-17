import SwiftUI

struct ImmersiveNowPlayingView: View {
    @ObservedObject var nowPlaying = NowPlayingManager.shared
    @ObservedObject var progress = PlaybackProgressManager.shared
    let onClose: () -> Void

    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0
    @State private var animateGradient = false
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with close button and ESC hint
            HStack {
                Spacer()
                Text("ESC to exit")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(8)
                    .background(.ultraThinMaterial.opacity(0.3))
                    .cornerRadius(6)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .help("Close immersive mode")
            }
            .padding()

            Spacer()

            // Main content
            HStack(alignment: .top, spacing: 40) {
                artworkView
                    .frame(width: 350, height: 350)

                VStack(alignment: .leading, spacing: 12) {
                    trackInfoView

                    Divider()
                        .background(Color.white.opacity(0.2))

                    lyricsView
                }
                .frame(maxWidth: 500)
            }
            .padding(.horizontal, 60)

            Spacer()

            // Controls at bottom
            controlsBar
        }
        .background {
            backgroundLayer
        }
        .ignoresSafeArea()
        .onAppear {
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Color.black

            if let artwork = nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 80)
                    .scaleEffect(1.3)
                    .opacity(0.4)
            }

            // Animated gradient overlay
            LinearGradient(
                colors: [
                    (nowPlaying.dominantColor ?? Color.blue).opacity(0.3),
                    Color.black.opacity(0.6),
                    Color.black.opacity(0.8)
                ],
                startPoint: animateGradient ? .topLeading : .topTrailing,
                endPoint: animateGradient ? .bottomTrailing : .bottomLeading
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                    animateGradient = true
                }
            }
        }
    }

    // MARK: - Artwork

    private var artworkView: some View {
        Group {
            if let artwork = nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .overlay {
                        Image(systemName: Icons.musicNote)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.white.opacity(0.3))
                            .padding(80)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: nowPlaying.currentTrack?.id)
    }

    // MARK: - Track Info

    private var trackInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(nowPlaying.currentTrack?.title ?? "No Track")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)

            Text(nowPlaying.currentTrack?.displayArtist ?? "")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)

            if let album = nowPlaying.currentTrack?.albumTitle {
                HStack(spacing: 8) {
                    Text(album)
                        .italic()

                    if let year = nowPlaying.currentTrack?.year {
                        Text("(\(String(year)))")
                    }

                    if let genre = nowPlaying.currentTrack?.genreName {
                        Text("·")
                        Text(genre)
                    }
                }
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
            }
        }
    }

    // MARK: - Lyrics

    private var lyricsView: some View {
        Group {
            if let lyrics = nowPlaying.lyrics {
                ScrollView(showsIndicators: false) {
                    ImmersiveLyricsContent(
                        lyrics: lyrics,
                        currentTime: progress.currentTime
                    )
                }
            } else if nowPlaying.lyricsState.isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                Text("No lyrics available")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(maxHeight: 300)
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        VStack(spacing: 12) {
            // Seek bar
            HStack(spacing: 8) {
                Text((isSeeking ? seekPosition : progress.currentTime).formattedDuration)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { isSeeking ? seekPosition : progress.currentTime },
                        set: { newValue in
                            seekPosition = newValue
                            if !isSeeking { isSeeking = true }
                        }
                    ),
                    in: 0...max(progress.duration, 0.01),
                    onEditingChanged: { editing in
                        if !editing {
                            nowPlaying.seek(to: seekPosition)
                            isSeeking = false
                        }
                    }
                )
                .tint(.white)

                Text(progress.duration.formattedDuration)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .leading)
            }

            // Transport controls
            HStack(spacing: 32) {
                Button(action: { nowPlaying.toggleShuffle() }) {
                    Image(systemName: Icons.shuffleFill)
                        .font(.system(size: 16))
                        .foregroundColor(nowPlaying.isShuffleEnabled ? .white : .white.opacity(0.4))
                }
                .buttonStyle(.plain)

                Button(action: { nowPlaying.previous() }) {
                    Image(systemName: Icons.previousFIll)
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button(action: { nowPlaying.togglePlayPause() }) {
                    Image(systemName: nowPlaying.playbackState == .playing ? Icons.pauseCircleFill : Icons.playCircleFill)
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button(action: { nowPlaying.next() }) {
                    Image(systemName: Icons.nextFill)
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button(action: { nowPlaying.cycleRepeatMode() }) {
                    Image(systemName: nowPlaying.repeatMode == .one ? Icons.repeat1Fill : Icons.repeatFill)
                        .font(.system(size: 16))
                        .foregroundColor(nowPlaying.repeatMode != .off ? .white : .white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            // Volume control
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))

                Slider(value: Binding(
                    get: { Double(nowPlaying.volume) },
                    set: { nowPlaying.setVolume(Float($0)) }
                ), in: 0...1)
                .tint(.white)
                .frame(width: 120)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 100)
        .padding(.bottom, 40)
        .padding(.top, 16)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            switch event.keyCode {
            case 53: // ESC
                onClose()
                return nil
            case 49: // Space
                nowPlaying.togglePlayPause()

                return nil
            case 123: // Left arrow
                nowPlaying.seek(to: max(0, progress.currentTime - 10))

                return nil
            case 124: // Right arrow
                nowPlaying.seek(to: min(progress.duration, progress.currentTime + 10))

                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

// MARK: - Immersive Lyrics Content

struct ImmersiveLyricsContent: View {
    let lyrics: String
    let currentTime: TimeInterval

    @State private var parsedLines: [LyricsLine] = []
    @State private var isSynced = false

    var body: some View {
        Group {
            if isSynced {
                syncedView
            } else {
                Text(lyrics)
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.leading)
            }
        }
        .onAppear { parseLines() }
        .onChange(of: lyrics) { _, _ in parseLines() }
    }

    private var syncedView: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(parsedLines.enumerated()), id: \.element.id) { index, line in
                    let isActive = index == activeLineIndex
                    let isPast = index < (activeLineIndex ?? 0)

                    Text(line.text)
                        .font(.system(size: isActive ? 22 : 17, weight: isActive ? .bold : .regular))
                        .foregroundColor(isActive ? .white : (isPast ? .white.opacity(0.3) : .white.opacity(0.5)))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, isActive ? 4 : 1)
                        .id(line.id)
                        .animation(.easeInOut(duration: 0.3), value: isActive)
                }
            }
            .onChange(of: activeLineIndex) { _, newIndex in
                if let newIndex, newIndex < parsedLines.count {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(parsedLines[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    private var activeLineIndex: Int? {
        guard !parsedLines.isEmpty else { return nil }
        var lastIndex: Int? = nil
        for (index, line) in parsedLines.enumerated() {
            if currentTime >= line.time {
                lastIndex = index
            } else {
                break
            }
        }
        return lastIndex
    }

    private func parseLines() {
        let lines = lyrics.components(separatedBy: .newlines)
        var result: [LyricsLine] = []

        for line in lines {
            guard line.hasPrefix("["), let closeBracket = line.firstIndex(of: "]") else { continue }
            let timeStr = String(line[line.index(after: line.startIndex)..<closeBracket])
            let text = String(line[line.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            let parts = timeStr.split(separator: ":")
            guard parts.count == 2, let minutes = Double(parts[0]) else { continue }
            let secParts = parts[1].split(separator: ".")
            guard secParts.count == 2, let seconds = Double(secParts[0]), let frac = Double(secParts[1]) else { continue }
            let divisor = secParts[1].count == 3 ? 1000.0 : 100.0
            let time = minutes * 60 + seconds + frac / divisor
            result.append(LyricsLine(time: time, text: text))
        }

        if result.count >= 3 {
            result.sort { $0.time < $1.time }
            parsedLines = result
            isSynced = true
        } else {
            isSynced = false
        }
    }
}

