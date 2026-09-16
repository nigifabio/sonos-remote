import XCTest
@testable import SonosRemote

/// Exercises the transport-control SOAP calls end to end through
/// `SonosController` (not just `SOAPClient` in isolation), using a fake
/// transport so no real Sonos hardware is needed — verifies both the exact
/// request `SonosController` builds and how it parses the response back.
final class SonosControllerTransportTests: XCTestCase {
    private let device = SonosDevice(uuid: "RINCON_TEST01400", name: "Kitchen", host: "10.0.0.50")

    func testPlaySendsPlayActionWithSpeedOne() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.play(device, transport: fake)

        let request = try XCTUnwrap(fake.recordedRequests.first)
        XCTAssertEqual(request.url.host, "10.0.0.50")
        XCTAssertEqual(request.url.port, 1400)
        XCTAssertEqual(request.soapAction, "\"urn:schemas-upnp-org:service:AVTransport:1#Play\"")
        XCTAssertEqual(request.argument("Speed"), "1")
    }

    func testPauseSendsPauseAction() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.pause(device, transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.soapAction, "\"urn:schemas-upnp-org:service:AVTransport:1#Pause\"")
    }

    func testTransportStateParsesCurrentTransportState() async throws {
        let fake = FakeSOAPTransport()
        fake.responses = [(200, FakeSOAPTransport.envelope("<u:GetTransportInfoResponse><CurrentTransportState>PLAYING</CurrentTransportState></u:GetTransportInfoResponse>"))]

        let state = try await SonosController.transportState(device, transport: fake)
        XCTAssertEqual(state, .playing)
        XCTAssertEqual(fake.recordedRequests.first?.soapAction, "\"urn:schemas-upnp-org:service:AVTransport:1#GetTransportInfo\"")
    }

    func testTransportStateReturnsUnknownForUnrecognizedValue() async throws {
        let fake = FakeSOAPTransport()
        fake.responses = [(200, FakeSOAPTransport.envelope("<u:GetTransportInfoResponse><CurrentTransportState>SOME_NEW_STATE</CurrentTransportState></u:GetTransportInfoResponse>"))]
        let state = try await SonosController.transportState(device, transport: fake)
        XCTAssertEqual(state, .unknown)
    }

    func testTrackInfoParsesTitleArtistAlbumAndUnescapesEntities() async throws {
        let fake = FakeSOAPTransport()
        let meta = """
        &lt;DIDL-Lite&gt;&lt;item&gt;&lt;dc:title&gt;Juice Newton&amp;apos;s Greatest Hits&lt;/dc:title&gt;&lt;dc:creator&gt;Juice Newton&lt;/dc:creator&gt;&lt;upnp:album&gt;Greatest Hits&lt;/upnp:album&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
        """
        fake.responses = [
            (200, FakeSOAPTransport.envelope("""
            <u:GetPositionInfoResponse>
              <TrackDuration>0:03:30</TrackDuration>
              <RelTime>0:01:00</RelTime>
              <TrackURI>http://10.0.0.50:1400/track.mp3</TrackURI>
              <TrackMetaData>\(meta)</TrackMetaData>
            </u:GetPositionInfoResponse>
            """)),
            (200, FakeSOAPTransport.envelope("<u:GetTransportInfoResponse><CurrentTransportState>PLAYING</CurrentTransportState></u:GetTransportInfoResponse>"))
        ]

        let info = try await SonosController.trackInfo(device, transport: fake)
        XCTAssertEqual(info.title, "Juice Newton's Greatest Hits")
        XCTAssertEqual(info.artist, "Juice Newton")
        XCTAssertEqual(info.album, "Greatest Hits")
        XCTAssertEqual(info.durationSeconds, 210)
        XCTAssertEqual(info.positionSeconds, 60)
        XCTAssertFalse(info.isStream)
    }

    func testTrackInfoDetectsStreamWhenPlayingWithZeroDuration() async throws {
        let fake = FakeSOAPTransport()
        fake.responses = [
            (200, FakeSOAPTransport.envelope("<u:GetPositionInfoResponse><TrackDuration>0:00:00</TrackDuration><RelTime>0:00:00</RelTime></u:GetPositionInfoResponse>")),
            (200, FakeSOAPTransport.envelope("<u:GetTransportInfoResponse><CurrentTransportState>PLAYING</CurrentTransportState></u:GetTransportInfoResponse>"))
        ]
        let info = try await SonosController.trackInfo(device, transport: fake)
        XCTAssertTrue(info.isStream)
    }

    func testNonSuccessResponseThrowsWithFaultString() async {
        let fake = FakeSOAPTransport()
        fake.responses = [(500, FakeSOAPTransport.envelope("<faultstring>Invalid InstanceID</faultstring>"))]

        do {
            try await SonosController.play(device, transport: fake)
            XCTFail("Expected play() to throw")
        } catch let error as SOAPError {
            XCTAssertTrue(error.message.contains("Invalid InstanceID"))
        } catch {
            XCTFail("Expected SOAPError, got \(error)")
        }
    }
}
