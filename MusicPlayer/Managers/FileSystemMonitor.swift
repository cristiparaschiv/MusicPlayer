import Foundation

class FileSystemMonitor {
    private var eventStream: FSEventStreamRef?
    private var monitoredPaths: [String] = []
    private let eventQueue = DispatchQueue(label: "com.orangemusicplayer.fsevents", qos: .background)

    var onPathsChanged: (() -> Void)?

    func startMonitoring(paths: [String]) {
        stopMonitoring()

        guard !paths.isEmpty else {
            return
        }

        monitoredPaths = paths

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (
            streamRef: ConstFSEventStreamRef,
            clientCallBackInfo: UnsafeMutableRawPointer?,
            numEvents: Int,
            eventPaths: UnsafeMutableRawPointer,
            eventFlags: UnsafePointer<FSEventStreamEventFlags>,
            eventIds: UnsafePointer<FSEventStreamEventId>
        ) in
            guard let info = clientCallBackInfo else { return }

            let monitor = Unmanaged<FileSystemMonitor>.fromOpaque(info).takeUnretainedValue()

            // Check if any events are relevant (created, modified, removed, renamed)
            let relevantFlags: FSEventStreamEventFlags = [
                FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
                FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved),
                FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified),
                FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
            ].reduce(0, |)

            var hasRelevantChanges = false
            for i in 0..<numEvents {
                let flags = eventFlags[i]
                if flags & relevantFlags != 0 {
                    hasRelevantChanges = true
                    break
                }
            }

            if hasRelevantChanges {
                // Debounce: wait a bit before notifying (files might still be copying)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    monitor.onPathsChanged?()
                }
            }
        }

        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // latency in seconds
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )

        if let stream = eventStream {
            FSEventStreamSetDispatchQueue(stream, eventQueue)
            FSEventStreamStart(stream)
            print("Started monitoring \(paths.count) paths for file system changes")
        }
    }

    func stopMonitoring() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
            print("Stopped file system monitoring")
        }
        monitoredPaths.removeAll()
    }

    deinit {
        stopMonitoring()
    }
}
