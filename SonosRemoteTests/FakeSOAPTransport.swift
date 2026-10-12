import Foundation
@testable import SonosRemote

/// Records every SOAP request sent through it and returns canned XML
/// responses in order, so `SonosController` functions can be tested against
/// exact request shape (host/action/arguments) and response parsing without
/// touching real Sonos hardware. One fresh instance per test — no shared
/// state between tests — and safe to call from several tasks at once.
final class FakeSOAPTransport: SOAPTransport {
    struct RecordedRequest {
        let url: URL
        let soapAction: String?
        let body: String

        /// Pulls `<Tag>value</Tag>` out of the raw SOAP request body — the
        /// simplest way to assert an argument's value without a real XML parser.
        func argument(_ tag: String) -> String? {
            guard let openRange = body.range(of: "<\(tag)>"),
                  let closeRange = body.range(of: "</\(tag)>", range: openRange.upperBound..<body.endIndex) else { return nil }
            return String(body[openRange.upperBound..<closeRange.lowerBound])
        }
    }

    private let lock = NSLock()
    private var recorded: [RecordedRequest] = []
    private var queued: [(statusCode: Int, body: String)] = []

    var recordedRequests: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    /// Queued (statusCode, body) pairs, consumed in order — one per request
    /// that has no entry in `responsesByAction`. If exhausted, (200, "").
    var responses: [(statusCode: Int, body: String)] {
        get { lock.lock(); defer { lock.unlock() }; return queued }
        set { lock.lock(); queued = newValue; lock.unlock() }
    }

    /// Fixed response per SOAP action name (e.g. "GetPositionInfo"). Use
    /// this when the code under test sends several requests at once, so the
    /// answer doesn't depend on which one happens to arrive first.
    var responsesByAction: [String: (statusCode: Int, body: String)] = [:]

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let bodyString = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let soapAction = request.value(forHTTPHeaderField: "SOAPACTION")
        let actionName = soapAction?.split(separator: "#").last.map { $0.replacingOccurrences(of: "\"", with: "") } ?? ""

        lock.lock()
        recorded.append(RecordedRequest(url: request.url!, soapAction: soapAction, body: bodyString))
        let (statusCode, body): (Int, String)
        if let fixed = responsesByAction[actionName] {
            (statusCode, body) = fixed
        } else {
            (statusCode, body) = queued.isEmpty ? (200, "") : queued.removeFirst()
        }
        lock.unlock()

        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }

    /// Wraps `innerXML` in the SOAP envelope shape `SOAPClient` expects back —
    /// use this to build canned responses without repeating the boilerplate.
    static func envelope(_ innerXML: String) -> String {
        """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>\(innerXML)</s:Body>
        </s:Envelope>
        """
    }
}
