import Foundation
import JavaScriptCore
import AppKit
import Combine
import AVFoundation
import AudioToolbox

final class ScriptingEngine: ObservableObject {
    static let shared = ScriptingEngine()

    @Published private(set) var scripts: [ScriptMetadata] = []

    private var contexts: [UUID: JSContext] = [:]
    private let scriptQueue = DispatchQueue(label: "com.orangemusicplayer.scripting", qos: .userInitiated)
    private let lock = NSLock()
    private var fileMonitor: FileSystemMonitor?
    private var notificationObservers: [NSObjectProtocol] = []

    private let trackDAO = TrackDAO()
    private let albumDAO = AlbumDAO()
    private let artistDAO = ArtistDAO()
    private let playlistDAO = PlaylistDAO()

    private init() {}

    // MARK: - Lifecycle

    func start() {
        ensureScriptsDirectory()
        loadScripts()
        startFileMonitoring()
        registerNotifications()
    }

    func shutdown() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        fileMonitor?.stopMonitoring()
        lock.lock()
        contexts.removeAll()
        lock.unlock()
    }

    // MARK: - Script Discovery

    private func ensureScriptsDirectory() {
        try? FileManager.default.createDirectory(
            at: Constants.scriptsDirectory,
            withIntermediateDirectories: true
        )
    }

    func loadScripts() {
        // Capture enabled state snapshot safely, then do work on scriptQueue
        let doLoad = { [weak self] (enabledSnapshot: [String: Bool]) in
            self?.scriptQueue.async { [weak self] in
                guard let self = self else { return }

                let fm = FileManager.default
                let scriptsDir = Constants.scriptsDirectory

                guard let files = try? fm.contentsOfDirectory(
                    at: scriptsDir,
                    includingPropertiesForKeys: nil
                ).filter({ $0.pathExtension == "js" }) else {
                    return
                }

                let existingEnabled = enabledSnapshot

            var newScripts: [ScriptMetadata] = []
            for file in files {
                if var meta = ScriptMetadata.parse(from: file) {
                    if let wasEnabled = existingEnabled[file.lastPathComponent] {
                        meta.isEnabled = wasEnabled
                    }
                    newScripts.append(meta)
                }
            }

            newScripts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            // Tear down old contexts
            self.lock.lock()
            self.contexts.removeAll()
            self.lock.unlock()

            DispatchQueue.main.async {
                self.scripts = newScripts
            }

            // Create contexts for enabled scripts
            for script in newScripts where script.isEnabled {
                self.createContext(for: script)
            }
        }
        }

        // Snapshot scripts on main thread, then dispatch work
        if Thread.isMainThread {
            var map: [String: Bool] = [:]
            for s in scripts { map[s.fileURL.lastPathComponent] = s.isEnabled }
            doLoad(map)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                var map: [String: Bool] = [:]
                for s in self.scripts { map[s.fileURL.lastPathComponent] = s.isEnabled }
                doLoad(map)
            }
        }
    }

    // MARK: - File Monitoring

    private func startFileMonitoring() {
        fileMonitor = FileSystemMonitor()
        fileMonitor?.onPathsChanged = { [weak self] in
            self?.loadScripts()
        }
        fileMonitor?.startMonitoring(paths: [Constants.scriptsDirectory.path])
    }

    // MARK: - Context Management

    private func createContext(for script: ScriptMetadata) {
        let context = JSContext()!

        let scriptName = script.name
        context.exceptionHandler = { [weak self] _, exception in
            let msg = exception?.toString() ?? "Unknown error"
            ScriptConsoleManager.shared.log(msg, from: scriptName, level: .error)
            DispatchQueue.main.async {
                self?.updateScriptStatus(id: script.id, status: .error(msg))
            }
        }

        injectConsole(into: context, scriptName: scriptName)
        injectOrangeAPI(into: context)

        if let source = try? String(contentsOf: script.fileURL, encoding: .utf8) {
            context.evaluateScript(source)
        }

        lock.lock()
        contexts[script.id] = context
        lock.unlock()
    }

    // MARK: - Console Bridge

    private func injectConsole(into context: JSContext, scriptName: String) {
        let consoleObj = JSValue(newObjectIn: context)!

        // Use JSValue to handle variadic console.log/warn/error calls
        let makeLogger = { (level: ConsoleEntry.ConsoleLevel) -> @convention(block) () -> Void in
            return {
                let args = JSContext.currentArguments() as? [JSValue] ?? []
                let message = args.map { $0.toString() ?? "undefined" }.joined(separator: " ")
                ScriptConsoleManager.shared.log(message.isEmpty ? "" : message, from: scriptName, level: level)
            }
        }
        let logBlock = makeLogger(.log)
        let warnBlock = makeLogger(.warn)
        let errorBlock = makeLogger(.error)

        consoleObj.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        consoleObj.setObject(warnBlock, forKeyedSubscript: "warn" as NSString)
        consoleObj.setObject(errorBlock, forKeyedSubscript: "error" as NSString)

        context.setObject(consoleObj, forKeyedSubscript: "console" as NSString)
    }

    // MARK: - Orange API Injection

    private func injectOrangeAPI(into context: JSContext) {
        let orange = JSValue(newObjectIn: context)!
        context.setObject(orange, forKeyedSubscript: "orange" as NSString)

        injectPlayerAPI(into: context)
        injectLibraryAPI(into: context)
        injectPlaylistsAPI(into: context)
        injectEffectsAPI(into: context)
        injectEventAPI(into: context)
    }

    // MARK: - Player API

    private func injectPlayerAPI(into context: JSContext) {
        let player = JSValue(newObjectIn: context)!

        let playBlock: @convention(block) () -> Void = {
            DispatchQueue.main.async { PlayerManager.shared.play() }
        }
        let pauseBlock: @convention(block) () -> Void = {
            DispatchQueue.main.async { PlayerManager.shared.pause() }
        }
        let stopBlock: @convention(block) () -> Void = {
            DispatchQueue.main.async { PlayerManager.shared.stop() }
        }
        let nextBlock: @convention(block) () -> Void = {
            DispatchQueue.main.async { PlayerManager.shared.next() }
        }
        let previousBlock: @convention(block) () -> Void = {
            DispatchQueue.main.async { PlayerManager.shared.previous() }
        }
        let seekBlock: @convention(block) (Double) -> Void = { seconds in
            DispatchQueue.main.async { PlayerManager.shared.seek(to: seconds) }
        }

        player.setObject(playBlock, forKeyedSubscript: "play" as NSString)
        player.setObject(pauseBlock, forKeyedSubscript: "pause" as NSString)
        player.setObject(stopBlock, forKeyedSubscript: "stop" as NSString)
        player.setObject(nextBlock, forKeyedSubscript: "next" as NSString)
        player.setObject(previousBlock, forKeyedSubscript: "previous" as NSString)
        player.setObject(seekBlock, forKeyedSubscript: "seek" as NSString)

        // Getter functions for read-only properties
        let getCurrentTrack: @convention(block) () -> [String: Any]? = {
            guard let track = PlayerManager.shared.currentTrack else { return nil }
            return Self.trackToDict(track)
        }
        let getPosition: @convention(block) () -> Double = {
            PlayerManager.shared.currentTime
        }
        let getIsPlaying: @convention(block) () -> Bool = {
            PlayerManager.shared.isPlaying
        }
        let getVolume: @convention(block) () -> Float = {
            PlayerManager.shared.volume
        }
        let setVolume: @convention(block) (Float) -> Void = { value in
            DispatchQueue.main.async { PlayerManager.shared.volume = value }
        }

        player.setObject(getCurrentTrack, forKeyedSubscript: "getCurrentTrack" as NSString)
        player.setObject(getPosition, forKeyedSubscript: "getPosition" as NSString)
        player.setObject(getIsPlaying, forKeyedSubscript: "getIsPlaying" as NSString)
        player.setObject(getVolume, forKeyedSubscript: "getVolume" as NSString)
        player.setObject(setVolume, forKeyedSubscript: "setVolume" as NSString)

        context.objectForKeyedSubscript("orange" as NSString)?.setObject(player, forKeyedSubscript: "player" as NSString)

        // Define getter properties via JS
        context.evaluateScript("""
            Object.defineProperty(orange.player, 'currentTrack', {
                get: function() { return orange.player.getCurrentTrack(); },
                configurable: true
            });
            Object.defineProperty(orange.player, 'position', {
                get: function() { return orange.player.getPosition(); },
                configurable: true
            });
            Object.defineProperty(orange.player, 'isPlaying', {
                get: function() { return orange.player.getIsPlaying(); },
                configurable: true
            });
            Object.defineProperty(orange.player, 'volume', {
                get: function() { return orange.player.getVolume(); },
                set: function(v) { orange.player.setVolume(v); },
                configurable: true
            });
        """)
    }

    // MARK: - Library API

    private func injectLibraryAPI(into context: JSContext) {
        let library = JSValue(newObjectIn: context)!

        let searchTracksBlock: @convention(block) (String) -> [[String: Any]] = { [weak self] query in
            guard let self = self else { return [] }
            return self.trackDAO.search(query: query).map { Self.trackToDict($0) }
        }
        let searchAlbumsBlock: @convention(block) (String) -> [[String: Any]] = { [weak self] query in
            guard let self = self else { return [] }
            return self.albumDAO.search(query: query).map { Self.albumToDict($0) }
        }
        let searchArtistsBlock: @convention(block) (String) -> [[String: Any]] = { [weak self] query in
            guard let self = self else { return [] }
            return self.artistDAO.search(query: query).map { Self.artistToDict($0) }
        }
        let getTrackBlock: @convention(block) (Int) -> [String: Any]? = { [weak self] id in
            guard let self = self else { return nil }
            return self.trackDAO.getById(id: Int64(id)).map { Self.trackToDict($0) }
        }
        let getAlbumBlock: @convention(block) (Int) -> [String: Any]? = { [weak self] id in
            guard let self = self else { return nil }
            return self.albumDAO.getById(id: Int64(id)).map { Self.albumToDict($0) }
        }

        library.setObject(searchTracksBlock, forKeyedSubscript: "searchTracks" as NSString)
        library.setObject(searchAlbumsBlock, forKeyedSubscript: "searchAlbums" as NSString)
        library.setObject(searchArtistsBlock, forKeyedSubscript: "searchArtists" as NSString)
        library.setObject(getTrackBlock, forKeyedSubscript: "getTrack" as NSString)
        library.setObject(getAlbumBlock, forKeyedSubscript: "getAlbum" as NSString)

        context.objectForKeyedSubscript("orange" as NSString)?.setObject(library, forKeyedSubscript: "library" as NSString)
    }

    // MARK: - Playlists API

    private func injectPlaylistsAPI(into context: JSContext) {
        let playlists = JSValue(newObjectIn: context)!

        let listBlock: @convention(block) () -> [[String: Any]] = { [weak self] in
            guard let self = self else { return [] }
            return self.playlistDAO.getAll().map { Self.playlistToDict($0) }
        }
        let createBlock: @convention(block) (String) -> Void = { name in
            PlaylistManager.shared.createPlaylist(name: name)
        }
        let deleteBlock: @convention(block) (Int) -> Void = { id in
            PlaylistManager.shared.deletePlaylist(id: Int64(id))
        }
        let addTrackBlock: @convention(block) (Int, Int) -> Void = { [weak self] playlistId, trackId in
            guard let self = self else { return }
            self.playlistDAO.addTrack(playlistId: Int64(playlistId), trackId: Int64(trackId))
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.playlistContentChanged,
                    object: nil,
                    userInfo: ["playlistId": Int64(playlistId)]
                )
            }
        }
        let removeTrackBlock: @convention(block) (Int, Int) -> Void = { [weak self] playlistId, trackId in
            guard let self = self else { return }
            self.playlistDAO.removeTrack(playlistId: Int64(playlistId), trackId: Int64(trackId))
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.Notifications.playlistContentChanged,
                    object: nil,
                    userInfo: ["playlistId": Int64(playlistId)]
                )
            }
        }
        let getTracksBlock: @convention(block) (Int) -> [[String: Any]] = { [weak self] playlistId in
            guard let self = self else { return [] }
            return self.playlistDAO.getTracksForPlaylist(playlistId: Int64(playlistId)).map { Self.trackToDict($0) }
        }

        playlists.setObject(listBlock, forKeyedSubscript: "list" as NSString)
        playlists.setObject(createBlock, forKeyedSubscript: "create" as NSString)
        playlists.setObject(deleteBlock, forKeyedSubscript: "delete" as NSString)
        playlists.setObject(addTrackBlock, forKeyedSubscript: "addTrack" as NSString)
        playlists.setObject(removeTrackBlock, forKeyedSubscript: "removeTrack" as NSString)
        playlists.setObject(getTracksBlock, forKeyedSubscript: "getTracks" as NSString)

        context.objectForKeyedSubscript("orange" as NSString)?.setObject(playlists, forKeyedSubscript: "playlists" as NSString)
    }

    // MARK: - Effects API

    private func injectEffectsAPI(into context: JSContext) {
        let effects = JSValue(newObjectIn: context)!

        let chainBlock: @convention(block) () -> [Any] = {
            let slots = EffectChainManager.shared.slots
            return slots.map { slot -> Any in
                guard let slot = slot else { return NSNull() }
                return [
                    "type": slot.slotType.rawValue,
                    "name": slot.displayName,
                    "manufacturer": slot.manufacturer,
                    "isBypassed": slot.isBypassed
                ] as [String: Any]
            }
        }

        let bypassBlock: @convention(block) (Int, Bool) -> Void = { index, bypassed in
            DispatchQueue.main.async {
                let mgr = EffectChainManager.shared
                guard index >= 0, index < mgr.slots.count, let slot = mgr.slots[index] else { return }
                if slot.isBypassed != bypassed {
                    mgr.toggleBypass(at: index)
                }
            }
        }

        let setParamBlock: @convention(block) (Int, Int, Float) -> Void = { slotIndex, paramAddress, value in
            let mgr = EffectChainManager.shared
            guard slotIndex >= 0, slotIndex < mgr.slots.count,
                  let slot = mgr.slots[slotIndex],
                  let auSlot = slot as? AUPluginSlot,
                  let au = auSlot.anyAudioUnit,
                  let param = au.parameterTree?.parameter(withAddress: AudioToolbox.AUParameterAddress(paramAddress)) else { return }
            param.value = value
        }

        let getParamBlock: @convention(block) (Int, Int) -> Float = { slotIndex, paramAddress in
            let mgr = EffectChainManager.shared
            guard slotIndex >= 0, slotIndex < mgr.slots.count,
                  let slot = mgr.slots[slotIndex],
                  let auSlot = slot as? AUPluginSlot,
                  let au = auSlot.anyAudioUnit,
                  let param = au.parameterTree?.parameter(withAddress: AudioToolbox.AUParameterAddress(paramAddress)) else { return 0 }
            return param.value
        }

        let loadPresetBlock: @convention(block) (Int, JSValue, String) -> Void = { slotIndex, preset, source in
            let mgr = EffectChainManager.shared
            guard slotIndex >= 0, slotIndex < mgr.slots.count,
                  let slot = mgr.slots[slotIndex],
                  let auSlot = slot as? AUPluginSlot,
                  let au = auSlot.anyAudioUnit else { return }

            if source == "factory" {
                guard let factoryPresets = au.factoryPresets else { return }
                if preset.isNumber {
                    let num = preset.toInt32()
                    if let p = factoryPresets.first(where: { $0.number == Int(num) }) {
                        au.currentPreset = p
                    }
                } else if preset.isString {
                    let name = preset.toString() ?? ""
                    if let p = factoryPresets.first(where: { $0.name == name }) {
                        au.currentPreset = p
                    }
                }
            } else if source == "user" {
                ScriptConsoleManager.shared.log("User presets not yet supported", from: "effects.loadPreset", level: .warn)
            }
        }

        effects.setObject(chainBlock, forKeyedSubscript: "chain" as NSString)
        effects.setObject(bypassBlock, forKeyedSubscript: "bypass" as NSString)
        effects.setObject(setParamBlock, forKeyedSubscript: "setParameter" as NSString)
        effects.setObject(getParamBlock, forKeyedSubscript: "getParameter" as NSString)
        effects.setObject(loadPresetBlock, forKeyedSubscript: "loadPreset" as NSString)

        context.objectForKeyedSubscript("orange" as NSString)?.setObject(effects, forKeyedSubscript: "effects" as NSString)
    }

    // MARK: - Event API

    private func injectEventAPI(into context: JSContext) {
        context.evaluateScript("""
            (function() {
                var _handlers = {};
                orange.on = function(event, callback) {
                    if (!_handlers[event]) _handlers[event] = [];
                    _handlers[event].push(callback);
                };
                orange._emit = function(event, data) {
                    var handlers = _handlers[event] || [];
                    for (var i = 0; i < handlers.length; i++) {
                        try { handlers[i](data); } catch(e) { console.error('Event handler error: ' + e); }
                    }
                };
            })();
        """)
    }

    // MARK: - Notification Handling

    private func registerNotifications() {
        let nc = NotificationCenter.default

        notificationObservers.append(nc.addObserver(
            forName: Constants.Notifications.trackDidChange, object: nil, queue: nil
        ) { [weak self] _ in
            self?.dispatchEvent("trackChanged") {
                guard let track = PlayerManager.shared.currentTrack else { return nil }
                return Self.trackToDict(track) as NSDictionary
            }
        })

        notificationObservers.append(nc.addObserver(
            forName: Constants.Notifications.playbackStateChanged, object: nil, queue: nil
        ) { [weak self] _ in
            let state = PlayerManager.shared.playbackState
            switch state {
            case .playing:
                self?.dispatchEvent("playbackStarted", dataProvider: nil)
            case .paused:
                self?.dispatchEvent("playbackPaused", dataProvider: nil)
            case .stopped:
                self?.dispatchEvent("playbackStopped", dataProvider: nil)
            }
        })

        notificationObservers.append(nc.addObserver(
            forName: Constants.Notifications.queueDidChange, object: nil, queue: nil
        ) { [weak self] _ in
            self?.dispatchEvent("queueChanged", dataProvider: nil)
        })

        notificationObservers.append(nc.addObserver(
            forName: Constants.Notifications.libraryDidUpdate, object: nil, queue: nil
        ) { [weak self] _ in
            self?.dispatchEvent("libraryUpdated", dataProvider: nil)
        })
    }

    private func dispatchEvent(_ eventName: String, dataProvider: (() -> NSObject?)? = nil) {
        scriptQueue.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let ctxs = self.contexts
            self.lock.unlock()

            let data = dataProvider?()

            for (_, context) in ctxs {
                if let emitFn = context.objectForKeyedSubscript("orange")?.objectForKeyedSubscript("_emit") {
                    if let data = data {
                        emitFn.call(withArguments: [eventName, data])
                    } else {
                        emitFn.call(withArguments: [eventName])
                    }
                }
            }
        }
    }

    // MARK: - Public API

    func runScript(id: UUID) {
        scriptQueue.async { [weak self] in
            guard let self = self else { return }
            guard let script = self.scripts.first(where: { $0.id == id }) else { return }

            DispatchQueue.main.async {
                self.updateScriptStatus(id: id, status: .running)
            }

            self.createContext(for: script)

            // Only reset to idle if the script didn't error (exception handler sets .error)
            DispatchQueue.main.async {
                if let idx = self.scripts.firstIndex(where: { $0.id == id }),
                   case .error = self.scripts[idx].status {
                    // Keep error status
                } else {
                    self.updateScriptStatus(id: id, status: .idle)
                }
            }
        }
    }

    func toggleScript(id: UUID) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts[index].isEnabled.toggle()

        let script = scripts[index]
        if script.isEnabled {
            scriptQueue.async { [weak self] in
                self?.createContext(for: script)
            }
        } else {
            lock.lock()
            contexts.removeValue(forKey: id)
            lock.unlock()
        }
    }

    func openScriptsFolder() {
        NSWorkspace.shared.open(Constants.scriptsDirectory)
    }

    // MARK: - Helpers

    private func updateScriptStatus(id: UUID, status: ScriptMetadata.ScriptStatus) {
        if let index = scripts.firstIndex(where: { $0.id == id }) {
            scripts[index].status = status
        }
    }

    static func trackToDict(_ track: Track) -> [String: Any] {
        var dict: [String: Any] = [
            "id": track.id,
            "title": track.title,
            "duration": track.duration,
            "filePath": track.filePath,
            "playCount": track.playCount,
            "isFavorite": track.isFavorite
        ]
        if let v = track.artistName { dict["artist"] = v }
        if let v = track.albumTitle { dict["album"] = v }
        if let v = track.genreName { dict["genre"] = v }
        if let v = track.trackNumber { dict["trackNumber"] = v }
        if let v = track.year { dict["year"] = v }
        if let v = track.rating { dict["rating"] = v }
        return dict
    }

    static func albumToDict(_ album: Album) -> [String: Any] {
        var dict: [String: Any] = [
            "id": album.id,
            "title": album.title,
            "trackCount": album.trackCount
        ]
        if let v = album.artistName { dict["artist"] = v }
        if let v = album.year { dict["year"] = v }
        return dict
    }

    static func artistToDict(_ artist: Artist) -> [String: Any] {
        return [
            "id": artist.id,
            "name": artist.name,
            "albumCount": artist.albumCount,
            "trackCount": artist.trackCount
        ]
    }

    static func playlistToDict(_ playlist: Playlist) -> [String: Any] {
        return [
            "id": playlist.id,
            "name": playlist.name,
            "trackCount": playlist.trackCount
        ]
    }
}
