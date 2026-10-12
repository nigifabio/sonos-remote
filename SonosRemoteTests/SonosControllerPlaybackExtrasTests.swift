import XCTest
@testable import SonosRemote

final class SonosControllerPlaybackExtrasTests: XCTestCase {
    private let device = SonosDevice(uuid: "RINCON_A01400", name: "Family Room", host: "10.0.0.50")
    private let avTransport = "urn:schemas-upnp-org:service:AVTransport:1"

    func testSeekSendsRelativeTimeAsHoursMinutesSeconds() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.seek(device, toSeconds: 3725, transport: fake)
        let request = try XCTUnwrap(fake.recordedRequests.first)
        XCTAssertEqual(request.soapAction, "\"\(avTransport)#Seek\"")
        XCTAssertEqual(request.argument("Unit"), "REL_TIME")
        XCTAssertEqual(request.argument("Target"), "1:02:05")
    }

    func testSeekClampsNegativeToZero() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.seek(device, toSeconds: -5, transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.argument("Target"), "0:00:00")
    }

    func testPlayModeIsReadFromTransportSettings() async throws {
        let fake = FakeSOAPTransport()
        fake.responses = [(200, FakeSOAPTransport.envelope("<u:GetTransportSettingsResponse><PlayMode>SHUFFLE_NOREPEAT</PlayMode><RecQualityMode>NOT_IMPLEMENTED</RecQualityMode></u:GetTransportSettingsResponse>"))]
        let mode = try await SonosController.playMode(device, transport: fake)
        XCTAssertEqual(mode, PlayMode(shuffle: true, repeatMode: .off))
        XCTAssertEqual(fake.recordedRequests.first?.soapAction, "\"\(avTransport)#GetTransportSettings\"")
    }

    func testSetPlayModeSendsTheSonosValue() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.setPlayMode(device, to: PlayMode(shuffle: false, repeatMode: .one), transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.argument("NewPlayMode"), "REPEAT_ONE")
    }

    func testFailedActionCarriesTheUPnPErrorCode() async {
        let fake = FakeSOAPTransport()
        fake.responses = [(500, FakeSOAPTransport.envelope("<s:Fault><faultstring>UPnPError</faultstring><detail><UPnPError><errorCode>712</errorCode></UPnPError></detail></s:Fault>"))]
        do {
            try await SonosController.setPlayMode(device, to: PlayMode(shuffle: true), transport: fake)
            XCTFail("Expected a failure")
        } catch let error as SOAPError {
            XCTAssertEqual(error.code, 712)
        } catch {
            XCTFail("Expected SOAPError, got \(error)")
        }
    }

    private let track = BrowseItem(id: "1", parentID: "", title: "One", subtitle: "", uri: "http://x/1.mp3",
                                   metadata: "<m/>", albumArtURL: nil, isContainer: false)

    func testAddToQueueAppendsWithoutTouchingPlayback() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.addToQueue(track, on: device, transport: fake)
        XCTAssertEqual(fake.recordedRequests.compactMap(\.soapAction), ["\"\(avTransport)#AddURIToQueue\""])
        XCTAssertEqual(fake.recordedRequests[0].argument("EnqueuedURI"), "http://x/1.mp3")
        XCTAssertEqual(fake.recordedRequests[0].argument("EnqueueAsNext"), "0")
    }

    func testAddToQueuePlayNext() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.addToQueue(track, on: device, playNext: true, transport: fake)
        XCTAssertEqual(fake.recordedRequests[0].argument("EnqueueAsNext"), "1")
    }

    func testSwitchToTVPointsAtTheSpeakersOwnTVInput() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.switchToTV(device, transport: fake)
        XCTAssertEqual(fake.recordedRequests.count, 1)
        XCTAssertEqual(fake.recordedRequests[0].argument("CurrentURI"), "x-sonos-htastream:RINCON_A01400:spdif")
    }

    func testSwitchToLineInSetsTheStreamThenPlays() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.switchToLineIn(device, transport: fake)
        XCTAssertEqual(fake.recordedRequests.compactMap(\.soapAction), ["\"\(avTransport)#SetAVTransportURI\"", "\"\(avTransport)#Play\""])
        XCTAssertEqual(fake.recordedRequests[0].argument("CurrentURI"), "x-rincon-stream:RINCON_A01400")
    }

    func testDeviceDescriptionDetectsInputs() {
        let beam = """
        <root><device><modelNumber>S14</modelNumber><modelName>Sonos Beam</modelName><displayVersion>18.8</displayVersion>
        <serviceList><service><serviceType>urn:schemas-sonos-com:service:HTControl:1</serviceType></service></serviceList></device></root>
        """
        let era = """
        <root><device><modelNumber>S41</modelNumber><modelName>Sonos Era 300</modelName><displayVersion>18.8</displayVersion>
        <serviceList><service><serviceType>urn:schemas-upnp-org:service:AudioIn:1</serviceType></service></serviceList></device></root>
        """
        let one = "<root><device><modelNumber>S18</modelNumber><modelName>Sonos One</modelName><displayVersion>18.8</displayVersion></device></root>"

        // A first-generation Move has the AudioIn service (Bluetooth) but no jack.
        let move = era.replacingOccurrences(of: "S41", with: "S17").replacingOccurrences(of: "Era 300", with: "Move")
        XCTAssertFalse(SonosController.parseDeviceDescription(move).hasLineIn)

        XCTAssertTrue(SonosController.parseDeviceDescription(beam).hasTVInput)
        XCTAssertFalse(SonosController.parseDeviceDescription(beam).hasLineIn)
        XCTAssertTrue(SonosController.parseDeviceDescription(era).hasLineIn)
        XCTAssertEqual(SonosController.parseDeviceDescription(one), SonosDeviceDescription(modelName: "Sonos One", modelNumber: "S18", displayVersion: "18.8"))
    }

    // MARK: - Households

    private func topologyResponse(_ zoneGroups: String) -> (statusCode: Int, body: String) {
        (200, FakeSOAPTransport.envelope("<u:GetZoneGroupStateResponse><ZoneGroupState>\(XMLHelpers.escapeXML("<ZoneGroupState><ZoneGroups>\(zoneGroups)</ZoneGroups></ZoneGroupState>"))</ZoneGroupState></u:GetZoneGroupStateResponse>"))
    }

    private let s2Topology = """
    <ZoneGroup Coordinator="RINCON_B" ID="RINCON_B:1"><ZoneGroupMember UUID="RINCON_B" ZoneName="Office" Location="http://10.0.0.11:1400/xml/device_description.xml"/><ZoneGroupMember UUID="RINCON_A" ZoneName="Bedroom" Location="http://10.0.0.10:1400/xml/device_description.xml"/></ZoneGroup>
    """
    private let s1Topology = """
    <ZoneGroup Coordinator="RINCON_Z" ID="RINCON_Z:9"><ZoneGroupMember UUID="RINCON_Z" ZoneName="amelia Room" Location="http://10.0.0.212:1400/xml/device_description.xml"/></ZoneGroup>
    """

    func testEveryGroupOfOneAnswerSharesAHouseholdID() async throws {
        let fake = FakeSOAPTransport()
        fake.responses = [topologyResponse(s2Topology)]
        let groups = try await SonosController.fetchTopology(bootstrapHost: "10.0.0.11", transport: fake)
        XCTAssertEqual(groups.map(\.householdID), ["RINCON_A"], "Lowest room UUID, whichever speaker answered")
    }

    func testMergedTopologyKeepsBothHouseholdsAndSkipsARepeat() async {
        let fake = FakeSOAPTransport()
        // Two S2 speakers describe the same household; the S1 speaker its own.
        fake.responses = [topologyResponse(s2Topology), topologyResponse(s2Topology), topologyResponse(s1Topology)]
        let groups = await SonosController.mergedTopology(fromHosts: ["10.0.0.11", "10.0.0.10", "10.0.0.212"], transport: fake)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.householdID)), ["RINCON_A", "RINCON_Z"])
    }
}
