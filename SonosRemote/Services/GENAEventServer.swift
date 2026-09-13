import Foundation
import Network

/// Tiny HTTP server that receives GENA (UPnP eventing) NOTIFY callbacks from
/// Sonos speakers and hands each one off for parsing. Runs continuously
/// alongside the app so state changes (play/pause, volume, track) arrive
/// as soon as they happen instead of waiting for the next poll.
final class GENAEventServer {
    static let shared = GENAEventServer()

    typealias NotifyHandler = (_ path: String, _ body: String) -> Void

    private var listener: NWListener?
    let port: NWEndpoint.Port = 57125
    private let queue = DispatchQueue(label: "com.fabionigi.SonosRemote.genaserver")
    var onNotify: NotifyHandler?

    func start() throws {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    /// The URL Sonos should POST NOTIFY requests to for a given subscription.
    func callbackURL(path: String) -> String? {
        guard let ip = LocalHTTPServer.primaryLANAddress() else { return nil }
        return "http://\(ip):\(port)\(path)"
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveFullRequest(on: connection, buffer: Data())
    }

    private func receiveFullRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var newBuffer = buffer
            if let data { newBuffer.append(data) }

            if let headerEndRange = newBuffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerText = String(data: newBuffer[..<headerEndRange.lowerBound], encoding: .utf8) ?? ""
                let contentLength = Self.contentLength(from: headerText)
                let bodyStart = headerEndRange.upperBound
                if newBuffer.count - bodyStart >= contentLength {
                    let bodyData = newBuffer[bodyStart..<(bodyStart + contentLength)]
                    let body = String(data: bodyData, encoding: .utf8) ?? ""
                    let path = Self.path(from: headerText)
                    self.respondOK(on: connection)
                    if let path { self.onNotify?(path, body) }
                    return
                }
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receiveFullRequest(on: connection, buffer: newBuffer)
        }
    }

    private func respondOK(on connection: NWConnection) {
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func contentLength(from headerText: String) -> Int {
        for line in headerText.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Content-Length") == .orderedSame {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private static func path(from headerText: String) -> String? {
        guard let firstLine = headerText.split(separator: "\r\n").first else { return nil }
        let components = firstLine.split(separator: " ")
        guard components.count >= 2 else { return nil }
        return String(components[1])
    }
}
