import XCTest
@testable import SonosRemote

/// Covers a real S1-relevant robustness fix: we used to assume every GENA
/// subscription grant was our requested 300s and schedule renewal on that
/// fixed assumption. A device is free to grant less — more likely on
/// older/embedded firmware (common on Sonos S1-era hardware) with tighter
/// subscription-tracking limits — which would let the subscription lapse
/// silently. Verified live: a real Sonos device (S2) returns "Second-300",
/// which this correctly parses to 300.
final class GENATimeoutParsingTests: XCTestCase {
    private func response(timeout: String?) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let timeout { headers["TIMEOUT"] = timeout }
        return HTTPURLResponse(
            url: URL(string: "http://10.0.0.10:1400/MediaRenderer/AVTransport/Event")!,
            statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers
        )!
    }

    func testParsesStandardTimeout() {
        XCTAssertEqual(GENASubscriptionManager.parseTimeoutSeconds(from: response(timeout: "Second-300")), 300)
    }

    func testParsesShorterTimeoutFromAMoreConservativeDevice() {
        XCTAssertEqual(GENASubscriptionManager.parseTimeoutSeconds(from: response(timeout: "Second-100")), 100)
    }

    func testFallsBackTo300ForInfiniteTimeout() {
        XCTAssertEqual(GENASubscriptionManager.parseTimeoutSeconds(from: response(timeout: "Second-infinite")), 300)
    }

    func testFallsBackTo300WhenHeaderMissing() {
        XCTAssertEqual(GENASubscriptionManager.parseTimeoutSeconds(from: response(timeout: nil)), 300)
    }

    func testFallsBackTo300ForMalformedHeader() {
        XCTAssertEqual(GENASubscriptionManager.parseTimeoutSeconds(from: response(timeout: "garbage")), 300)
    }
}
