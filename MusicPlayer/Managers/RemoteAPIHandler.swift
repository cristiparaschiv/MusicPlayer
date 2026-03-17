import Foundation
import AppKit

class RemoteAPIHandler {

    func handleRequest(method: String, path: String, body: Data?) -> (Int, String, Data) {
        let components = path.components(separatedBy: "?")
        let route = components[0]
        let queryString = components.count > 1 ? components[1] : ""
        let params = parseQueryParams(queryString)

        switch (method, route) {
        case ("GET", "/api/status"):
            return getStatus()
        case ("POST", "/api/playback/play"):
            DispatchQueue.main.async { PlayerManager.shared.play() }
            return ok()
        case ("POST", "/api/playback/pause"):
            DispatchQueue.main.async { PlayerManager.shared.pause() }
            return ok()
        case ("POST", "/api/playback/toggle"):
            DispatchQueue.main.async { PlayerManager.shared.togglePlayPause() }
            return ok()
        case ("POST", "/api/playback/next"):
            DispatchQueue.main.async { PlayerManager.shared.next() }
            return ok()
        case ("POST", "/api/playback/previous"):
            DispatchQueue.main.async { PlayerManager.shared.previous() }
            return ok()
        case ("POST", "/api/playback/seek"):
            if let timeStr = params["t"], let time = Double(timeStr) {
                DispatchQueue.main.async { PlayerManager.shared.seek(to: time) }
                return ok()
            }
            return badRequest("Missing parameter: t")
        case ("POST", "/api/playback/volume"):
            if let levelStr = params["level"], let level = Float(levelStr) {
                DispatchQueue.main.async { PlayerManager.shared.setVolume(max(0, min(1, level))) }
                return ok()
            }
            return badRequest("Missing parameter: level")
        case ("POST", "/api/playback/shuffle"):
            DispatchQueue.main.async { PlayerManager.shared.toggleShuffle() }
            return ok()
        case ("POST", "/api/playback/repeat"):
            DispatchQueue.main.async { PlayerManager.shared.cycleRepeatMode() }
            return ok()
        case ("GET", "/api/queue"):
            return getQueue()
        case ("POST", "/api/queue/skip"):
            if let indexStr = params["index"], let index = Int(indexStr) {
                DispatchQueue.main.async {
                    if let track = QueueManager.shared.skipToTrack(at: index) {
                        PlayerManager.shared.play(track: track)
                    }
                }
                return ok()
            }
            return badRequest("Missing parameter: index")
        case ("GET", "/api/artwork"):
            return getArtwork()
        default:
            return (404, "application/json", jsonData(["error": "not found"]))
        }
    }

    // MARK: - Response Builders

    private func getStatus() -> (Int, String, Data) {
        let np = NowPlayingManager.shared
        let qm = QueueManager.shared

        var dict: [String: Any] = [
            "state": np.playbackState.rawValue,
            "currentTime": PlaybackProgressManager.shared.currentTime,
            "duration": PlaybackProgressManager.shared.duration,
            "volume": np.volume,
            "shuffle": np.isShuffleEnabled,
            "repeat": np.repeatMode.rawValue,
            "queueIndex": qm.currentTrackIndex,
            "queueCount": qm.queueCount,
            "hasArtwork": np.artwork != nil,
        ]

        if let track = np.currentTrack {
            dict["track"] = trackDict(track)
        }

        return (200, "application/json", jsonData(dict))
    }

    private func getQueue() -> (Int, String, Data) {
        let queue = QueueManager.shared.currentQueue
        let currentIndex = QueueManager.shared.currentTrackIndex
        let tracks = queue.enumerated().map { (i, track) -> [String: Any] in
            var d = trackDict(track)
            d["isCurrent"] = (i == currentIndex)
            return d
        }
        let dict: [String: Any] = [
            "tracks": tracks,
            "currentIndex": currentIndex,
        ]
        return (200, "application/json", jsonData(dict))
    }

    private func getArtwork() -> (Int, String, Data) {
        guard let image = NowPlayingManager.shared.artwork else {
            return (404, "application/json", jsonData(["error": "no artwork"]))
        }

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return (500, "application/json", jsonData(["error": "encoding failed"]))
        }

        return (200, "image/jpeg", jpeg)
    }

    // MARK: - Helpers

    private func trackDict(_ track: Track) -> [String: Any] {
        var d: [String: Any] = [
            "id": track.id,
            "title": track.title,
            "artist": track.displayArtist,
            "album": track.displayAlbum,
            "duration": track.duration,
            "formattedDuration": track.formattedDuration,
        ]
        if let trackNumber = track.trackNumber { d["trackNumber"] = trackNumber }
        if let year = track.year { d["year"] = year }
        if let genre = track.genreName { d["genre"] = genre }
        d["isFavorite"] = track.isFavorite
        return d
    }

    private func ok() -> (Int, String, Data) {
        (200, "application/json", jsonData(["ok": true]))
    }

    private func badRequest(_ message: String) -> (Int, String, Data) {
        (400, "application/json", jsonData(["error": message]))
    }

    private func jsonData(_ dict: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{\"error\":\"json\"}".utf8)
    }

    private func parseQueryParams(_ query: String) -> [String: String] {
        var params: [String: String] = [:]
        for pair in query.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 {
                params[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        return params
    }

    // MARK: - Embedded HTML

    // swiftlint:disable function_body_length
    func embeddedHTML() -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
        <title>Orange Music Player</title>
        <style>
        :root {
          --accent: #F77F00;
          --accent-dim: #c46300;
          --bg: #1a1a1a;
          --bg2: #242424;
          --bg3: #2e2e2e;
          --text: #f0f0f0;
          --text2: #999;
          --radius: 12px;
        }
        * { margin:0; padding:0; box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', 'Helvetica Neue', sans-serif;
          background: var(--bg); color: var(--text);
          min-height: 100vh; min-height: 100dvh;
          display: flex; flex-direction: column;
          overflow-x: hidden;
        }
        .header {
          padding: 12px 16px; text-align: center;
          background: var(--bg2); border-bottom: 1px solid #333;
        }
        .header h1 { font-size: 15px; font-weight: 600; color: var(--accent); }
        .tabs {
          display: flex; background: var(--bg2); border-bottom: 1px solid #333;
        }
        .tab {
          flex: 1; padding: 10px; text-align: center; font-size: 13px; font-weight: 500;
          color: var(--text2); border: none; background: none; cursor: pointer;
          border-bottom: 2px solid transparent; transition: all 0.2s;
        }
        .tab.active { color: var(--accent); border-bottom-color: var(--accent); }
        .content { flex: 1; overflow-y: auto; padding-bottom: env(safe-area-inset-bottom, 0); }
        .panel { display: none; }
        .panel.active { display: block; }
        .np { padding: 24px 16px; display: flex; flex-direction: column; align-items: center; }
        .artwork-wrap {
          width: min(280px, 70vw); height: min(280px, 70vw);
          border-radius: var(--radius); overflow: hidden;
          background: var(--bg3); box-shadow: 0 8px 32px rgba(0,0,0,0.4);
          margin-bottom: 24px;
        }
        .artwork-wrap img { width: 100%; height: 100%; object-fit: cover; }
        .no-art {
          width: 100%; height: 100%; display: flex; align-items: center;
          justify-content: center; font-size: 48px; color: #555;
        }
        .track-info { text-align: center; width: 100%; max-width: 320px; margin-bottom: 20px; }
        .track-title { font-size: 18px; font-weight: 700; margin-bottom: 4px;
                       overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .track-artist { font-size: 14px; color: var(--text2);
                        overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .seek-wrap { width: 100%; max-width: 320px; margin-bottom: 20px; }
        .seek-times { display: flex; justify-content: space-between; font-size: 11px; color: var(--text2); margin-top: 4px; }
        input[type=range] {
          -webkit-appearance: none; width: 100%; height: 4px; border-radius: 2px;
          background: var(--bg3); outline: none;
        }
        input[type=range]::-webkit-slider-thumb {
          -webkit-appearance: none; width: 14px; height: 14px; border-radius: 50%;
          background: var(--accent); cursor: pointer;
        }
        .transport { display: flex; align-items: center; gap: 20px; margin-bottom: 20px; }
        .btn {
          background: none; border: none; color: var(--text); cursor: pointer;
          font-size: 22px; padding: 8px; border-radius: 50%; transition: background 0.15s;
          display: flex; align-items: center; justify-content: center;
        }
        .btn:hover { background: var(--bg3); }
        .btn:active { background: #444; }
        .btn-play { font-size: 32px; background: var(--accent); color: #fff; width: 56px; height: 56px; border-radius: 50%; }
        .btn-play:hover { background: var(--accent-dim); }
        .btn-small { font-size: 16px; }
        .btn-active { color: var(--accent); }
        .volume-wrap { display: flex; align-items: center; gap: 10px; width: 100%; max-width: 280px; margin-bottom: 8px; }
        .vol-icon { font-size: 16px; color: var(--text2); min-width: 20px; text-align: center; }
        .queue-list { padding: 8px 0; }
        .queue-item {
          display: flex; align-items: center; padding: 10px 16px; gap: 12px;
          cursor: pointer; transition: background 0.15s;
        }
        .queue-item:hover { background: var(--bg3); }
        .queue-item.current { background: var(--bg3); border-left: 3px solid var(--accent); }
        .qi-num { font-size: 12px; color: var(--text2); min-width: 24px; text-align: center; }
        .qi-info { flex: 1; overflow: hidden; }
        .qi-title { font-size: 14px; font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .qi-artist { font-size: 12px; color: var(--text2); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .qi-dur { font-size: 12px; color: var(--text2); }
        .queue-empty { text-align: center; padding: 40px 16px; color: var(--text2); font-size: 14px; }
        @media (min-width: 600px) {
          .artwork-wrap { width: 300px; height: 300px; }
          .np { padding: 32px; }
        }
        </style>
        </head>
        <body>
        <div class="header"><h1>Orange Music Player</h1></div>
        <div class="tabs">
          <button class="tab active" onclick="showTab('now-playing')">Now Playing</button>
          <button class="tab" onclick="showTab('queue')">Queue</button>
        </div>
        <div class="content">
          <div id="now-playing" class="panel active">
            <div class="np">
              <div class="artwork-wrap">
                <img id="artwork" src="/api/artwork" onerror="this.style.display='none';document.getElementById('no-art').style.display='flex'" />
                <div id="no-art" class="no-art" style="display:none">&#9835;</div>
              </div>
              <div class="track-info">
                <div class="track-title" id="title">&mdash;</div>
                <div class="track-artist" id="artist">&mdash;</div>
              </div>
              <div class="seek-wrap">
                <input type="range" id="seek" min="0" max="100" value="0" step="0.5"
                       oninput="seeking=true" onchange="doSeek(this.value)" />
                <div class="seek-times">
                  <span id="time-cur">0:00</span>
                  <span id="time-dur">0:00</span>
                </div>
              </div>
              <div class="transport">
                <button class="btn btn-small" id="btn-shuffle" onclick="api('POST','/api/playback/shuffle')">&#8645;</button>
                <button class="btn" onclick="api('POST','/api/playback/previous')">&#9198;</button>
                <button class="btn btn-play" id="btn-play" onclick="api('POST','/api/playback/toggle')">&#9654;</button>
                <button class="btn" onclick="api('POST','/api/playback/next')">&#9197;</button>
                <button class="btn btn-small" id="btn-repeat" onclick="api('POST','/api/playback/repeat')">&#8634;</button>
              </div>
              <div class="volume-wrap">
                <span class="vol-icon">&#128264;</span>
                <input type="range" id="volume" min="0" max="1" step="0.02" value="0.8"
                       oninput="api('POST','/api/playback/volume?level='+this.value)" />
                <span class="vol-icon">&#128266;</span>
              </div>
            </div>
          </div>
          <div id="queue" class="panel">
            <div id="queue-list" class="queue-list">
              <div class="queue-empty">Queue is empty</div>
            </div>
          </div>
        </div>
        <script>
        var seeking = false;
        var lastArtworkTrackId = null;
        var currentTab = 'now-playing';

        function showTab(name) {
          var tabs = document.querySelectorAll('.tab');
          tabs[0].classList.toggle('active', name === 'now-playing');
          tabs[1].classList.toggle('active', name === 'queue');
          document.querySelectorAll('.panel').forEach(function(p) {
            p.classList.toggle('active', p.id === name);
          });
          currentTab = name;
          if (name === 'queue') fetchQueue();
        }

        function api(method, path) {
          fetch(path, { method: method }).catch(function() {});
        }

        function fmtTime(s) {
          if (!s || s < 0) return '0:00';
          var m = Math.floor(s / 60), sec = Math.floor(s % 60);
          return m + ':' + (sec < 10 ? '0' : '') + sec;
        }

        function doSeek(val) {
          seeking = false;
          api('POST', '/api/playback/seek?t=' + val);
        }

        function poll() {
          fetch('/api/status').then(function(r) { return r.json(); }).then(function(d) {
            document.getElementById('title').textContent = d.track ? d.track.title : '\\u2014';
            document.getElementById('artist').textContent = d.track ? d.track.artist : '\\u2014';

            if (!seeking) {
              var seek = document.getElementById('seek');
              seek.max = d.duration || 100;
              seek.value = d.currentTime || 0;
              document.getElementById('time-cur').textContent = fmtTime(d.currentTime);
              document.getElementById('time-dur').textContent = fmtTime(d.duration);
            }

            document.getElementById('volume').value = d.volume;

            var playBtn = document.getElementById('btn-play');
            playBtn.textContent = d.state === 'playing' ? '\\u23F8' : '\\u25B6';

            document.getElementById('btn-shuffle').classList.toggle('btn-active', d.shuffle);
            var repBtn = document.getElementById('btn-repeat');
            repBtn.classList.toggle('btn-active', d.repeat !== 'off');
            repBtn.textContent = d.repeat === 'one' ? '\\u21BA1' : '\\u21BA';

            var tid = d.track ? d.track.id : null;
            if (tid !== lastArtworkTrackId) {
              lastArtworkTrackId = tid;
              var img = document.getElementById('artwork');
              var noArt = document.getElementById('no-art');
              if (d.hasArtwork) {
                img.src = '/api/artwork?_=' + Date.now();
                img.style.display = '';
                noArt.style.display = 'none';
              } else {
                img.style.display = 'none';
                noArt.style.display = 'flex';
              }
            }
          }).catch(function() {});
        }

        function fetchQueue() {
          fetch('/api/queue').then(function(r) { return r.json(); }).then(function(d) {
            var list = document.getElementById('queue-list');
            while (list.firstChild) list.removeChild(list.firstChild);

            if (!d.tracks || d.tracks.length === 0) {
              var empty = document.createElement('div');
              empty.className = 'queue-empty';
              empty.textContent = 'Queue is empty';
              list.appendChild(empty);
              return;
            }

            d.tracks.forEach(function(t, i) {
              var item = document.createElement('div');
              item.className = 'queue-item' + (t.isCurrent ? ' current' : '');
              item.onclick = function() { api('POST', '/api/queue/skip?index=' + i); };

              var num = document.createElement('span');
              num.className = 'qi-num';
              num.textContent = (i + 1).toString();

              var info = document.createElement('div');
              info.className = 'qi-info';
              var title = document.createElement('div');
              title.className = 'qi-title';
              title.textContent = t.title;
              var artist = document.createElement('div');
              artist.className = 'qi-artist';
              artist.textContent = t.artist;
              info.appendChild(title);
              info.appendChild(artist);

              var dur = document.createElement('span');
              dur.className = 'qi-dur';
              dur.textContent = t.formattedDuration;

              item.appendChild(num);
              item.appendChild(info);
              item.appendChild(dur);
              list.appendChild(item);
            });
          }).catch(function() {});
        }

        setInterval(poll, 1000);
        setInterval(function() { if (currentTab === 'queue') fetchQueue(); }, 2000);
        poll();
        </script>
        </body>
        </html>
        """
    }
    // swiftlint:enable function_body_length
}
