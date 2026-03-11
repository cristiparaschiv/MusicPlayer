import Foundation
import Combine
import CommonCrypto

class LastFMManager: ObservableObject {
    static let shared = LastFMManager()

    private let apiKey = Constants.lastFMAPIKey
    private let apiSecret = Secrets.lastFMSharedSecret
    private let baseURL = "https://ws.audioscrobbler.com/2.0/"

    @Published var isAuthenticated: Bool = false
    @Published var username: String = ""

    private var sessionKey: String?
    private var scrobbleTimer: Timer?
    private var currentTrackStartTime: Date?
    private var currentTrackId: Int64?
    private var isScrobblingEnabled: Bool = true

    private let scrobbleDAO = LastFMScrobbleDAO()

    private init() {
        loadSession()
        retryFailedScrobbles()
    }

    // MARK: - Authentication (auth.getMobileSession)

    func authenticate(username: String, password: String, completion: @escaping (Result<String, Error>) -> Void) {
        let params: [String: String] = [
            "method": "auth.getMobileSession",
            "username": username,
            "password": password,
            "api_key": apiKey
        ]

        let signedParams = signParams(params)

        guard var components = URLComponents(string: baseURL) else {
            completion(.failure(NSError(domain: "LastFM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid base URL"])))
            return
        }
        components.queryItems = signedParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems?.append(URLQueryItem(name: "format", value: "json"))

        guard let componentURL = components.url else {
            completion(.failure(NSError(domain: "LastFM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: componentURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // POST body
        let bodyString = signedParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = (bodyString + "&format=json").data(using: .utf8)
        request.url = URL(string: baseURL)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let session = json["session"] as? [String: Any],
                  let key = session["key"] as? String,
                  let name = session["name"] as? String else {
                let errorMsg = "Authentication failed"
                DispatchQueue.main.async { completion(.failure(NSError(domain: "LastFM", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg]))) }
                return
            }

            DispatchQueue.main.async {
                self?.sessionKey = key
                self?.username = name
                self?.isAuthenticated = true
                self?.saveSession(key: key, username: name)
                completion(.success(name))
            }
        }.resume()
    }

    func logout() {
        sessionKey = nil
        username = ""
        isAuthenticated = false
        deleteKeychainSession()
        UserDefaults.standard.removeObject(forKey: "lastfm_session_key")
        UserDefaults.standard.removeObject(forKey: "lastfm_username")
    }

    // MARK: - Now Playing

    func updateNowPlaying(track: Track) {
        guard isAuthenticated, isScrobblingEnabled, let sessionKey = sessionKey else { return }

        currentTrackStartTime = Date()
        currentTrackId = track.id

        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "artist": track.displayArtist,
            "track": track.title,
            "api_key": apiKey,
            "sk": sessionKey
        ]

        if let album = track.albumTitle {
            params["album"] = album
        }
        let duration = Int(track.duration)
        if duration > 0 {
            params["duration"] = "\(duration)"
        }

        sendSignedRequest(params: params) { _ in }
    }

    // MARK: - Scrobble

    func scrobbleIfEligible(track: Track) {
        guard isAuthenticated, isScrobblingEnabled else { return }
        guard let startTime = currentTrackStartTime, currentTrackId == track.id else { return }

        // Last.fm rules: >50% played OR >4 minutes played
        let elapsed = Date().timeIntervalSince(startTime)
        let halfDuration = track.duration / 2.0
        let isEligible = elapsed >= halfDuration || elapsed >= 240

        guard isEligible else { return }

        scrobble(track: track, timestamp: startTime)
        currentTrackStartTime = nil // Prevent double scrobble
    }

    private func scrobble(track: Track, timestamp: Date) {
        guard let sessionKey = sessionKey else { return }

        var params: [String: String] = [
            "method": "track.scrobble",
            "artist": track.displayArtist,
            "track": track.title,
            "timestamp": "\(Int(timestamp.timeIntervalSince1970))",
            "api_key": apiKey,
            "sk": sessionKey
        ]

        if let album = track.albumTitle {
            params["album"] = album
        }

        sendSignedRequest(params: params) { [weak self] success in
            if !success {
                // Queue for retry
                self?.scrobbleDAO.queueScrobble(
                    trackTitle: track.title,
                    artist: track.displayArtist,
                    album: track.albumTitle,
                    timestamp: timestamp
                )
            }
        }
    }

    // MARK: - Offline Queue Retry

    func retryFailedScrobbles() {
        guard isAuthenticated, let sessionKey = sessionKey else { return }

        let pending = scrobbleDAO.getPendingScrobbles(limit: 50)
        guard !pending.isEmpty else { return }

        for entry in pending {
            var params: [String: String] = [
                "method": "track.scrobble",
                "artist": entry.artist,
                "track": entry.trackTitle,
                "timestamp": "\(Int(entry.timestamp.timeIntervalSince1970))",
                "api_key": apiKey,
                "sk": sessionKey
            ]

            if let album = entry.album {
                params["album"] = album
            }

            sendSignedRequest(params: params) { [weak self] success in
                if success {
                    self?.scrobbleDAO.deleteScrobble(id: entry.id)
                }
            }
        }
    }

    // MARK: - Settings

    var scrobblingEnabled: Bool {
        get { isScrobblingEnabled }
        set {
            isScrobblingEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKeys.lastFMScrobblingEnabled)
        }
    }

    // MARK: - API Helpers

    private func signParams(_ params: [String: String]) -> [String: String] {
        var allParams = params
        let sortedKeys = allParams.keys.sorted()
        var sigString = ""
        for key in sortedKeys {
            sigString += key + (allParams[key] ?? "")
        }
        sigString += apiSecret

        let sig = md5(sigString)
        allParams["api_sig"] = sig
        return allParams
    }

    private func sendSignedRequest(params: [String: String], completion: @escaping (Bool) -> Void) {
        let signedParams = signParams(params)

        guard let url = URL(string: baseURL) else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = signedParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&") + "&format=json"
        request.httpBody = bodyString.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard error == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            let success = json["error"] == nil
            DispatchQueue.main.async { completion(success) }
        }.resume()
    }

    private func md5(_ string: String) -> String {
        let data = Data(string.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_MD5(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Session Persistence (Keychain)

    private static let keychainService = "com.orangemusicplayer.lastfm"
    private static let keychainAccount = "session_key"

    private func saveSession(key: String, username: String) {
        // Store session key in Keychain
        let keyData = key.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = keyData
        SecItemAdd(addQuery as CFDictionary, nil)

        // Username is non-sensitive, keep in UserDefaults
        UserDefaults.standard.set(username, forKey: "lastfm_username")

        // Migrate: remove old UserDefaults session key if present
        UserDefaults.standard.removeObject(forKey: "lastfm_session_key")
    }

    private func loadSession() {
        // Try Keychain first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) {
            sessionKey = key
        } else {
            // Migrate from UserDefaults if present
            if let legacyKey = UserDefaults.standard.string(forKey: "lastfm_session_key") {
                sessionKey = legacyKey
                // Re-save to Keychain and remove from UserDefaults
                let username = UserDefaults.standard.string(forKey: "lastfm_username") ?? ""
                saveSession(key: legacyKey, username: username)
            }
        }

        username = UserDefaults.standard.string(forKey: "lastfm_username") ?? ""
        isAuthenticated = sessionKey != nil
        isScrobblingEnabled = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.lastFMScrobblingEnabled) as? Bool ?? true
    }

    private func deleteKeychainSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
