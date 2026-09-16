import Foundation
@testable import SonosRemote

/// Records every SOAP request sent through it and returns canned XML
/// responses in order, so `SonosController` functions can be tested against
/// exact request shape (host/action/arguments) and response parsing without
/// touching real Sonos hardware. One fresh instance per test — no shared
/// state, so nothing here can flake under parallel test execution.
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

    private(set) var recordedRequests: [RecordedRequest] = []

    /// Queued (statusCode, body) pairs, consumed in order — one per request.
    /// If exhausted, further requests get (200, "").
    var responses: [(statusCode: Int, body: String)] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let bodyString = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        recordedRequests.append(RecordedRequest(
            url: request.url!,
            soapAction: request.value(forHTTPHeaderField: "SOAPACTION"),
            body: bodyString
        ))
        let (statusCode, body) = responses.isEmpty ? (200, "") : responses.removeFirst()
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
