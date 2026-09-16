import Foundation

enum SonosService: String {
    case avTransport = "AVTransport"
    case renderingControl = "RenderingControl"
    case groupRenderingControl = "GroupRenderingControl"
    case zoneGroupTopology = "ZoneGroupTopology"
    case contentDirectory = "ContentDirectory"
    case alarmClock = "AlarmClock"

    var urn: String {
        switch self {
        case .zoneGroupTopology:
            return "urn:schemas-upnp-org:service:ZoneGroupTopology:1"
        default:
            return "urn:schemas-upnp-org:service:\(rawValue):1"
        }
    }

    var controlPath: String {
        switch self {
        case .avTransport: return "/MediaRenderer/AVTransport/Control"
        case .renderingControl: return "/MediaRenderer/RenderingControl/Control"
        case .groupRenderingControl: return "/MediaRenderer/GroupRenderingControl/Control"
        case .zoneGroupTopology: return "/ZoneGroupTopology/Control"
        case .contentDirectory: return "/MediaServer/ContentDirectory/Control"
        case .alarmClock: return "/AlarmClock/Control"
        }
    }
}

struct SOAPError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum SOAPClient {
    /// Sends a SOAP action to a Sonos device and returns the raw XML response body.
    static func call(
        host: String,
        service: SonosService,
        action: String,
        arguments: [(String, String)] = [("InstanceID", "0")],
        transport: SOAPTransport = URLSession.shared
    ) async throws -> String {
        guard let url = URL(string: "http://\(host):1400\(service.controlPath)") else {
            throw SOAPError(message: "Bad URL for host \(host)")
        }

        let argsXML = arguments
            .map { "<\($0.0)>\(XMLHelpers.escapeXML($0.1))</\($0.0)>" }
            .joined()

        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body>
        <u:\(action) xmlns:u="\(service.urn)">
        \(argsXML)
        </u:\(action)>
        </s:Body>
        </s:Envelope>
        """

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service.urn)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await transport.data(for: request)
        let text = String(data: data, encoding: .utf8) ?? ""

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let faultString = XMLHelpers.value(ofTag: "errorDescription", in: text)
                ?? XMLHelpers.value(ofTag: "faultstring", in: text)
                ?? "HTTP \(http.statusCode)"
            throw SOAPError(message: "\(action) failed on \(host): \(faultString)")
        }

        return text
    }
}
