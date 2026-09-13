import XCTest
@testable import SonosRemote

final class MusicServiceTests: XCTestCase {
    func testDetectsSpotifyFromTrackURI() {
        // Real TrackURI captured live from the Sonos system during development.
        let uri = "x-sonos-spotify:spotify%3atrack%3a6NVB6W7G3svCKe5zB7kY8q?sid=9&flags=8232&sn=2"
        XCTAssertEqual(MusicService.detect(from: uri), .spotify)
    }

    func testDetectsAppleMusic() {
        XCTAssertEqual(MusicService.detect(from: "x-sonos-http:applemusic%3atrack%3a123.mp4"), .appleMusic)
    }

    func testEmptyURIIsUnknown() {
        XCTAssertEqual(MusicService.detect(from: ""), .unknown)
    }

    func testOtherURIIsLocal() {
        XCTAssertEqual(MusicService.detect(from: "x-file-cifs://nas/music/track.mp3"), .local)
    }

    func testTrackInfoComputesServiceFromSourceURI() {
        var info = TrackInfo()
        info.sourceURI = "x-sonos-spotify:spotify%3atrack%3aabc"
        XCTAssertEqual(info.service, .spotify)
    }
}
