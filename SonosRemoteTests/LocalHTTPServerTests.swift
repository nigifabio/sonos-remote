import XCTest
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
}
