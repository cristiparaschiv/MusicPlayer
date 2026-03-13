import Foundation

class FileSystemMonitor {
    private var eventStream: FSEventStreamRef?
    private var monitoredPaths: [String] = []
    private let eventQueue = DispatchQueue(label: "com.orangemusicplayer.fsevents", qos: .background)
    private var retainedSelf: Unmanaged<FileSystemMonitor>?
    private var debounceWorkItem: DispatchWorkItem?

    var onPathsChanged: (() -> Void)?

    func startMonitoring(paths: [String]) {
        stopMonitoring()

        // Filter out network volumes — FSEvents is unreliable on network mounts
        let localPaths = paths.filter { !MediaScannerManager.isNetworkVolume(path: $0) }

        guard !localPaths.isEmpty else {
            return
        }

        monitoredPaths = localPaths

        // Retain self for the duration of monitoring to prevent dangling pointer
        retainedSelf = Unmanaged.passRetained(self)

        var context = FSEventStreamContext(
            version: 0,
            info: retainedSelf!.toOpaque(),
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
                // Debounce: cancel previous and schedule new notification
                monitor.debounceWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak monitor] in
                    monitor?.onPathsChanged?()
                }
                monitor.debounceWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
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
        }
    }

    func stopMonitoring() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        monitoredPaths.removeAll()

        // Release the retained reference now that callbacks are fully stopped
        if let retained = retainedSelf {
            retained.release()
            retainedSelf = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}
