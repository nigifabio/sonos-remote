import Foundation
import Network

/// A tiny single-file HTTP server so Sonos speakers (which fetch audio over
/// HTTP GET) can pull the just-recorded intercom clip from this Mac.
final class LocalHTTPServer {
    static let shared = LocalHTTPServer()

    private var listener: NWListener?
    private let port: NWEndpoint.Port = 57123
    private var servedData: Data = Data()
    private let servedPath = "/intercom.wav"
    private let queue = DispatchQueue(label: "com.fabionigi.SonosRemote.httpserver")

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

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let firstLine = request.split(separator: "\r\n").first.map(String.init) ?? ""
            if firstLine.contains(self.servedPath) {
                let body = self.servedData
                let header = "HTTP/1.1 200 OK\r\n" +
                    "Content-Type: audio/wav\r\n" +
                    "Content-Length: \(body.count)\r\n" +
                    "Connection: close\r\n\r\n"
                var response = Data(header.utf8)
                response.append(body)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else {
                let notFound = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(notFound.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
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
