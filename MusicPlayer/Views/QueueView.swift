import SwiftUI

struct QueueView: View {
    @ObservedObject var nowPlaying = NowPlayingManager.shared
    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Up Next", systemImage: Icons.musicNoteList)
                    .font(.headline)
                Spacer()
                Text("\(nowPlaying.queue.count) tracks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !nowPlaying.queue.isEmpty {
                    Button(action: {
                        showingClearConfirmation = true
                    }) {
                        Text("Clear")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.clear)
            .alert("Clear Queue", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    QueueManager.shared.clearQueue()
                }
            } message: {
                Text("Are you sure you want to clear the queue?")
            }

            Divider()

            if nowPlaying.queue.isEmpty {
                emptyQueueView
            } else {
                QueueTableView(
                    tracks: nowPlaying.queue,
                    currentTrackIndex: nowPlaying.currentTrackIndex,
                    onPlayTrack: { index in
                        playTrack(at: index)
                    },
                    onReorder: { from, to in
                        QueueManager.shared.moveTrack(from: from, to: to)
                    },
                    onRemove: { index in
                        QueueManager.shared.removeTrack(at: index)
                    }
                )
            }
        }
        .frame(minWidth: 280)
        .background(.clear)
    }

    private var emptyQueueView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: Icons.musicNoteList)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Queue is Empty")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text("Add tracks to start playing")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func playTrack(at index: Int) {
        if index < nowPlaying.queue.count {
            let track = nowPlaying.queue[index]
            _ = QueueManager.shared.skipToTrack(at: index)
            nowPlaying.play(track: track)
        }
    }
}
