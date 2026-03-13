import Foundation
import Network
import Combine

class RemoteServerManager: ObservableObject {
    static let shared = RemoteServerManager()

    @Published private(set) var isRunning = false
    @Published private(set) var serverURL: String?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.orangemusicplayer.remote", qos: .userInitiated)
    private var apiHandler: RemoteAPIHandler?

    var port: UInt16 {
        get { UInt16(UserDefaults.standard.integer(forKey: Constants.UserDefaultsKeys.remoteControlPort)).nonZero ?? 8080 }
        set { UserDefaults.standard.set(Int(newValue), forKey: Constants.UserDefaultsKeys.remoteControlPort) }
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.remoteControlEnabled) }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKeys.remoteControlEnabled)
            if newValue { start() } else { stop() }
        }
    }

    private init() {
        apiHandler = RemoteAPIHandler()
    }

    func startIfEnabled() {
        if isEnabled { start() }
    }

    func start() {
        stop()

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            #if DEBUG
            print("[RemoteServer] Failed to create listener: \(error)")
            #endif
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.updateServerURL()
                    #if DEBUG
                    print("[RemoteServer] Listening on port \(self?.port ?? 0)")
                    #endif
                case .failed(let error):
                    #if DEBUG
                    print("[RemoteServer] Failed: \(error)")
                    #endif
                    self?.isRunning = false
                    self?.serverURL = nil
                case .cancelled:
                    self?.isRunning = false
                    self?.serverURL = nil
                default:
                    break
                }
                NotificationCenter.default.post(name: Constants.Notifications.remoteServerStateChanged, object: nil)
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.serverURL = nil
            NotificationCenter.default.post(name: Constants.Notifications.remoteServerStateChanged, object: nil)
        }
    }

    private func updateServerURL() {
        if let ip = getLocalIPAddress() {
            serverURL = "http://\(ip):\(port)"
        }
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }

            let request = String(data: data, encoding: .utf8) ?? ""
            let (method, path) = self.parseHTTPRequest(request)

            var body: Data?
            if method == "POST", let range = request.range(of: "\r\n\r\n") {
                let bodyString = String(request[range.upperBound...])
                body = bodyString.data(using: .utf8)
            }

            let response: (Int, String, Data)

            if path == "/" || path == "/index.html" {
                response = self.serveStaticFile("index.html", contentType: "text/html")
            } else if path.hasPrefix("/api/") {
                response = self.apiHandler?.handleRequest(method: method, path: path, body: body)
                    ?? (500, "application/json", Data("{\"error\":\"internal\"}".utf8))
            } else {
                response = (404, "text/plain", Data("Not Found".utf8))
            }

            let httpResponse = self.buildHTTPResponse(status: response.0, contentType: response.1, body: response.2)
            connection.send(content: httpResponse, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func parseHTTPRequest(_ request: String) -> (String, String) {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return ("GET", "/") }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return ("GET", "/") }
        return (parts[0], parts[1])
    }

    private func buildHTTPResponse(status: Int, contentType: String, body: Data) -> Data {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 404: statusText = "Not Found"
        case 400: statusText = "Bad Request"
        default: statusText = "Internal Server Error"
        }

        var header = "HTTP/1.1 \(status) \(statusText)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        var data = Data(header.utf8)
        data.append(body)
        return data
    }

    private func serveStaticFile(_ filename: String, contentType: String) -> (Int, String, Data) {
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "remote"),
              let data = try? Data(contentsOf: url) else {
            if filename == "index.html", let html = apiHandler?.embeddedHTML() {
                return (200, contentType, Data(html.utf8))
            }
            return (404, "text/plain", Data("File not found".utf8))
        }
        return (200, contentType, data)
    }

    // MARK: - Network Utilities

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
}

private extension UInt16 {
    var nonZero: UInt16? { self == 0 ? nil : self }
}
