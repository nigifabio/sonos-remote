import Foundation
import Network

/// A tiny HTTP server with three jobs:
/// - serve the just-recorded intercom/announcement clip to Sonos speakers
///   (which fetch audio over plain HTTP GET);
/// - serve files from the user's Local Library folder (`/library/...`);
/// - accept control requests (`/api/...`) from other programs **on this
///   Mac only**, e.g. the Sonos MCP server asking for an announcement.
final class LocalHTTPServer {
    static let shared = LocalHTTPServer()

    /// A parsed control request, handed to `controlHandler`.
    struct ControlRequest: Equatable {
        let method: String
        let path: String
        let body: Data
    }

    struct ControlResponse: Equatable {
        let status: Int
        let json: Data

        static func json(_ status: Int, _ object: [String: Any]) -> ControlResponse {
            ControlResponse(status: status, json: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8))
        }
    }

    typealias ControlHandler = (ControlRequest) async -> ControlResponse

    private var listener: NWListener?
    private let port: NWEndpoint.Port = 57123
    private var servedData: Data = Data()
    private let servedPath = LocalHTTPServer.announcementPath
    static let announcementPath = "/intercom.wav"

    /// Whether a track URI is one of this app's own intercom/announcement
    /// clips — which shouldn't count as "music that was played".
    static func isAnnouncementURI(_ uri: String) -> Bool {
        uri.hasPrefix("http://") && URL(string: uri)?.path == announcementPath
    }
    private var libraryRoot: URL?
    private var controlHandler: ControlHandler?
    private let queue = DispatchQueue(label: "com.fabionigi.SonosRemote.httpserver")
    private static let maxRequestBytes = 64 * 1024

    /// Swaps in new audio to serve and ensures the listener is running.
    /// Returns the URL Sonos speakers should fetch on the LAN.
    func serve(data: Data) throws -> URL {
        queue.sync { servedData = data } // serialize against `handle`, which reads servedData on `queue`
        if listener == nil {
            try start()
        }
        guard let ip = LocalHTTPServer.primaryLANAddress() else {
            throw SOAPError(message: "Could not determine this Mac's LAN IP address")
        }
        return URL(string: "http://\(ip):\(port)\(servedPath)")!
    }

    /// Sets (or clears, with `nil`) the folder that `/library/...` requests
    /// are served from — the user's configured Local Library folder. Starts
    /// the listener if it isn't already running.
    func setLibraryRoot(_ url: URL?) {
        queue.sync { libraryRoot = url }
        guard url != nil, listener == nil else { return }
        try? start()
    }

    /// Installs the handler for `/api/...` requests and starts listening.
    func startControlAPI(_ handler: @escaping ControlHandler) {
        queue.sync { controlHandler = handler }
        if listener == nil { try? start() }
    }

    private func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("LocalHTTPServer failed: \(error)")
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    // MARK: - Request parsing (pure, unit tested)

    struct ParsedRequest: Equatable {
        let method: String
        let path: String
        let headers: [String: String] // keys lowercased
        let body: Data
    }

    enum ParseResult: Equatable {
        case needMoreData
        case invalid
        case complete(ParsedRequest)
    }

    /// Parses an HTTP/1.x request from what has arrived so far. A request
    /// with a body is only complete once `Content-Length` bytes are in.
    static func parseRequest(_ buffer: Data) -> ParseResult {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > maxRequestBytes ? .invalid : .needMoreData
        }
        guard let headerText = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            headers[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        guard contentLength >= 0, contentLength <= maxRequestBytes else { return .invalid }
        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= contentLength else { return .needMoreData }
        return .complete(ParsedRequest(
            method: String(requestLine[0]).uppercased(), path: String(requestLine[1]), headers: headers,
            body: Data(buffer[bodyStart..<(bodyStart + contentLength)])
        ))
    }

    /// Whether a connection comes from this Mac itself.
    static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address == .loopback
        case .ipv6(let address): return address == .loopback || (address.isIPv4Mapped && address.asIPv4 == .loopback)
        case .name(let name, _): return name == "localhost"
        @unknown default: return false
        }
    }

    /// Why a control request must be refused before it reaches the handler,
    /// or nil when it may proceed. Control requests are for local programs:
    /// a web page open in a browser on this Mac is also "local", so anything
    /// a browser would send cross-site is turned away — a request carrying
    /// an `Origin`, or a POST that isn't declared as JSON (a page can only
    /// send JSON after a preflight this server never approves).
    static func controlRefusal(for request: ParsedRequest, fromLoopback: Bool) -> (status: Int, reason: String)? {
        guard fromLoopback else { return (403, "Control requests are only accepted from this Mac") }
        if request.headers["origin"] != nil { return (403, "Requests from web pages are not accepted") }
        if request.method == "POST" {
            let contentType = request.headers["content-type"]?.lowercased() ?? ""
            guard contentType.hasPrefix("application/json") else { return (415, "Send JSON (Content-Type: application/json)") }
        }
        return nil
    }

    /// Resolves a `/library/...` request path against `root`, rejecting
    /// anything that would escape it (e.g. a `..` component). Pure and
    /// side-effect-free (no disk I/O) so it can be unit tested directly
    /// instead of only through a live HTTP round-trip.
    static func resolvedLibraryFileURL(requestPath: String, root: URL) -> URL? {
        guard requestPath.hasPrefix(LocalLibraryService.pathPrefix) else { return nil }
        let encodedRelative = String(requestPath.dropFirst(LocalLibraryService.pathPrefix.count))
        guard let relative = encodedRelative.removingPercentEncoding, !relative.isEmpty,
              !relative.split(separator: "/").contains("..") else { return nil }

        let fileURL = root.appendingPathComponent(relative)
        let standardizedFile = fileURL.standardizedFileURL.path
        let standardizedRoot = root.standardizedFileURL.path
        guard standardizedFile.hasPrefix(standardizedRoot + "/") else { return nil }
        return fileURL
    }

    // MARK: - Connections

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var newBuffer = buffer
            if let data { newBuffer.append(data) }

            switch Self.parseRequest(newBuffer) {
            case .complete(let request):
                self.route(request, on: connection)
            case .invalid:
                self.respond(connection, status: 400, contentType: "text/plain", data: Data())
            case .needMoreData:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: newBuffer)
                }
            }
        }
    }

    /// Runs on `queue`.
    private func route(_ request: ParsedRequest, on connection: NWConnection) {
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path

        if path == servedPath {
            respond(connection, status: 200, contentType: "audio/wav", data: servedData)
        } else if path.hasPrefix(LocalLibraryService.pathPrefix), let root = libraryRoot,
                  let (data, contentType) = readLibraryFile(requestPath: path, root: root) {
            respond(connection, status: 200, contentType: contentType, data: data)
        } else if path.hasPrefix("/api/") {
            if let refusal = Self.controlRefusal(for: request, fromLoopback: Self.isLoopback(connection.endpoint)) {
                respond(connection, ControlResponse.json(refusal.status, ["ok": false, "error": refusal.reason]))
                return
            }
            guard let handler = controlHandler else {
                respond(connection, ControlResponse.json(503, ["ok": false, "error": "Sonos Remote is still starting"]))
                return
            }
            let controlRequest = ControlRequest(method: request.method, path: path, body: request.body)
            Task { [weak self] in
                let response = await handler(controlRequest)
                self?.queue.async { self?.respond(connection, response) }
            }
        } else {
            respond(connection, status: 404, contentType: "text/plain", data: Data())
        }
    }

    /// Resolves and reads a `/library/...` request. Runs on `queue`.
    private func readLibraryFile(requestPath: String, root: URL) -> (Data, String)? {
        guard let fileURL = LocalHTTPServer.resolvedLibraryFileURL(requestPath: requestPath, root: root),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return (data, LocalLibraryService.contentType(forExtension: fileURL.pathExtension))
    }

    private func respond(_ connection: NWConnection, _ response: ControlResponse) {
        respond(connection, status: response.status, contentType: "application/json", data: response.json)
    }

    private func respond(_ connection: NWConnection, status: Int, contentType: String, data: Data) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 415: reason = "Unsupported Media Type"
        case 503: reason = "Service Unavailable"
        default: reason = "Error"
        }
        let header = "HTTP/1.1 \(status) \(reason)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(data.count)\r\n" +
            "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// First non-loopback IPv4 address on an active interface (e.g. en0).
    static func primaryLANAddress() -> String? {
        var address: String?
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0,
                  let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue } // Wi-Fi/Ethernet, skip utun/awdl/etc.

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
            break
        }
        return address
    }
}
