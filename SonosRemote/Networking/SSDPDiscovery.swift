import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Minimal SSDP client: sends an M-SEARCH for Sonos ZonePlayers and collects
/// the IP addresses that reply. We don't need multicast group membership
/// since M-SEARCH replies are unicast back to our ephemeral source port.
enum SSDPDiscovery {
    static func discoverHosts(timeout: TimeInterval = 3.0) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: discoverHostsBlocking(timeout: timeout))
            }
        }
    }

    private static func discoverHostsBlocking(timeout: TimeInterval) -> [String] {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return [] }
        defer { close(sock) }

        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var localAddr = sockaddr_in()
        localAddr.sin_family = sa_family_t(AF_INET)
        localAddr.sin_addr.s_addr = INADDR_ANY
        localAddr.sin_port = 0
        let bindResult = withUnsafePointer(to: &localAddr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return [] }

        let message = "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: 239.255.255.250:1900\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: 2\r\n" +
            "ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n"
        let messageData = [UInt8](message.utf8)

        var destAddr = sockaddr_in()
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = UInt16(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &destAddr.sin_addr)

        _ = withUnsafePointer(to: &destAddr) { ptr -> Int in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                messageData.withUnsafeBufferPointer { buf in
                    sendto(sock, buf.baseAddress, buf.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        // Send twice in case of packet loss on the first attempt.
        _ = withUnsafePointer(to: &destAddr) { ptr -> Int in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                messageData.withUnsafeBufferPointer { buf in
                    sendto(sock, buf.baseAddress, buf.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        var hosts = Set<String>()
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 4096)

        while Date() < deadline {
            var fromAddr = sockaddr()
            var fromLen = socklen_t(MemoryLayout<sockaddr>.size)
            let n = buffer.withUnsafeMutableBufferPointer { buf in
                recvfrom(sock, buf.baseAddress, buf.count, 0, &fromAddr, &fromLen)
            }
            if n > 0 {
                let response = String(decoding: buffer[0..<n], as: UTF8.self)
                if let location = extractHeader("LOCATION", from: response),
                   let host = URL(string: location)?.host {
                    hosts.insert(host)
                }
            }
            // On timeout recvfrom returns -1 with EAGAIN/EWOULDBLOCK; loop continues until deadline.
        }
        return Array(hosts)
    }

    /// SSDP responses are HTTP-style headers, not XML — extract "Header: value".
    private static func extractHeader(_ name: String, from response: String) -> String? {
        for line in response.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
