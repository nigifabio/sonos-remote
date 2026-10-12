import XCTest
import Network
@testable import SonosRemote

/// Covers `LocalHTTPServer.resolvedLibraryFileURL` — the path-traversal
/// guard for `/library/...` requests — without needing a live HTTP
/// round-trip (that part was verified manually against real Sonos hardware,
/// but the guard itself deserves a regression test since it's
/// security-relevant and easy to weaken by accident in a later edit).
final class LocalHTTPServerTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Users/test/Music", isDirectory: true)

    func testResolvesSimpleFileName() {
        let url = LocalHTTPServer.resolvedLibraryFileURL(requestPath: "/library/song.mp3", root: root)
        XCTAssertEqual(url?.path, "/Users/test/Music/song.mp3")
    }

    func testResolvesPercentEncodedSpacesParensAndHash() {
        let url = LocalHTTPServer.resolvedLibraryFileURL(
            requestPath: "/library/My%20Song%20(Demo)%20%232.wav", root: root
        )
        XCTAssertEqual(url?.path, "/Users/test/Music/My Song (Demo) #2.wav")
    }

    func testResolvesNestedSubfolderPath() {
        let url = LocalHTTPServer.resolvedLibraryFileURL(requestPath: "/library/Sub%20Folder/track.mp3", root: root)
        XCTAssertEqual(url?.path, "/Users/test/Music/Sub Folder/track.mp3")
    }

    func testRejectsPathMissingTheLibraryPrefix() {
        XCTAssertNil(LocalHTTPServer.resolvedLibraryFileURL(requestPath: "/intercom.wav", root: root))
        XCTAssertNil(LocalHTTPServer.resolvedLibraryFileURL(requestPath: "/song.mp3", root: root))
    }

    func testRejectsEmptyRelativePath() {
        XCTAssertNil(LocalHTTPServer.resolvedLibraryFileURL(requestPath: "/library/", root: root))
    }

    func testRejectsPlainDotDotTraversal() {
        XCTAssertNil(LocalHTTPServer.resolvedLibraryFileURL(requestPath: "/library/../etc/passwd", root: root))
    }

    func testRejectsPercentEncodedDotDotTraversal() {
        XCTAssertNil(LocalHTTPServer.resolvedLibraryFileURL(
            requestPath: "/library/..%2F..%2F..%2Fetc%2Fpasswd", root: root
        ))
    }

    func testRejectsDotDotBuriedInsideANestedPath() {
        XCTAssertNil(LocalHTTPServer.resolvedLibraryFileURL(
            requestPath: "/library/Album/../../../etc/passwd", root: root
        ))
    }

    /// A filename that merely *contains* two dots (not a literal ".."
    /// path component) must still be served — the guard is component-based,
    /// not a naive substring check.
    func testDoesNotFalsePositiveOnFilenameContainingDoubleDots() {
        let url = LocalHTTPServer.resolvedLibraryFileURL(requestPath: "/library/track..final.mp3", root: root)
        XCTAssertEqual(url?.path, "/Users/test/Music/track..final.mp3")
    }

    // MARK: - request parsing

    private func request(_ text: String) -> Data { Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8) }

    func testParsesACompleteGet() {
        let result = LocalHTTPServer.parseRequest(request("GET /intercom.wav HTTP/1.1\nHost: 10.0.0.5:57123\n\n"))
        guard case .complete(let parsed) = result else { return XCTFail("Expected a complete request, got \(result)") }
        XCTAssertEqual(parsed.method, "GET")
        XCTAssertEqual(parsed.path, "/intercom.wav")
        XCTAssertEqual(parsed.headers["host"], "10.0.0.5:57123")
        XCTAssertTrue(parsed.body.isEmpty)
    }

    func testWaitsForTheWholeBodyOfAPost() {
        let head = "POST /api/announce HTTP/1.1\nContent-Type: application/json\nContent-Length: 14\n\n"
        XCTAssertEqual(LocalHTTPServer.parseRequest(request(head + "{\"text\"")), .needMoreData)
        guard case .complete(let parsed) = LocalHTTPServer.parseRequest(request(head + "{\"text\":\"hi!\"}")) else {
            return XCTFail("Expected a complete request")
        }
        XCTAssertEqual(String(data: parsed.body, encoding: .utf8), "{\"text\":\"hi!\"}")
    }

    func testHeadersNotYetCompleteNeedMoreData() {
        XCTAssertEqual(LocalHTTPServer.parseRequest(request("GET /api/status HTTP/1.1\nHost: x")), .needMoreData)
    }

    func testRejectsAnOversizedBodyAndGarbage() {
        XCTAssertEqual(LocalHTTPServer.parseRequest(request("POST /api/announce HTTP/1.1\nContent-Length: 99999999\n\n")), .invalid)
        XCTAssertEqual(LocalHTTPServer.parseRequest(request("nonsense\n\n")), .invalid)
    }

    // MARK: - who may send control requests

    private func parsed(_ method: String, headers: [String: String] = [:]) -> LocalHTTPServer.ParsedRequest {
        LocalHTTPServer.ParsedRequest(method: method, path: "/api/announce", headers: headers, body: Data())
    }

    func testControlRequestsFromAnotherMachineAreRefused() {
        let refusal = LocalHTTPServer.controlRefusal(for: parsed("POST", headers: ["content-type": "application/json"]), fromLoopback: false)
        XCTAssertEqual(refusal?.status, 403)
    }

    /// A page open in a browser on this Mac is "local" too. It can't send
    /// JSON cross-site without a preflight, and it always sends an Origin.
    func testControlRequestsABrowserPageCouldSendAreRefused() {
        XCTAssertEqual(LocalHTTPServer.controlRefusal(for: parsed("POST", headers: ["content-type": "text/plain"]), fromLoopback: true)?.status, 415)
        XCTAssertEqual(LocalHTTPServer.controlRefusal(for: parsed("POST"), fromLoopback: true)?.status, 415)
        XCTAssertEqual(LocalHTTPServer.controlRefusal(
            for: parsed("POST", headers: ["content-type": "application/json", "origin": "https://example.com"]), fromLoopback: true
        )?.status, 403)
        XCTAssertEqual(LocalHTTPServer.controlRefusal(for: parsed("GET", headers: ["origin": "https://example.com"]), fromLoopback: true)?.status, 403)
    }

    func testLocalJSONControlRequestsAreAccepted() {
        XCTAssertNil(LocalHTTPServer.controlRefusal(for: parsed("POST", headers: ["content-type": "application/json; charset=utf-8"]), fromLoopback: true))
        XCTAssertNil(LocalHTTPServer.controlRefusal(for: parsed("GET"), fromLoopback: true))
    }

    func testLoopbackDetection() {
        XCTAssertTrue(LocalHTTPServer.isLoopback(.hostPort(host: "127.0.0.1", port: 50000)))
        XCTAssertTrue(LocalHTTPServer.isLoopback(.hostPort(host: "::1", port: 50000)))
        XCTAssertTrue(LocalHTTPServer.isLoopback(.hostPort(host: "::ffff:127.0.0.1", port: 50000)))
        XCTAssertFalse(LocalHTTPServer.isLoopback(.hostPort(host: "10.0.0.153", port: 50000)))
        XCTAssertFalse(LocalHTTPServer.isLoopback(.hostPort(host: "::ffff:10.0.0.153", port: 50000)))
    }
}
