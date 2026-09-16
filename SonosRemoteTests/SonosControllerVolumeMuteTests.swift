import XCTest
@testable import SonosRemote

final class SonosControllerVolumeMuteTests: XCTestCase {
    private let device = SonosDevice(uuid: "RINCON_A01400", name: "Kitchen", host: "10.0.0.50")
    private let coordinator = SonosDevice(uuid: "RINCON_A01400", name: "Kitchen", host: "10.0.0.50")
    private lazy var group = SonosGroup(id: "g1", coordinatorUUID: coordinator.uuid, members: [coordinator])

    func testVolumeParsesCurrentVolumeOnMasterChannel() async throws {
        let fake = FakeSOAPTransport()
        fake.responses = [(200, FakeSOAPTransport.envelope("<u:GetVolumeResponse><CurrentVolume>42</CurrentVolume></u:GetVolumeResponse>"))]

        let volume = try await SonosController.volume(device, transport: fake)
        XCTAssertEqual(volume, 42)
        XCTAssertEqual(fake.recordedRequests.first?.argument("Channel"), "Master")
    }

    func testSetVolumeClampsToZeroAndHundred() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.setVolume(device, to: 150, transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.argument("DesiredVolume"), "100")

        try await SonosController.setVolume(device, to: -20, transport: fake)
        XCTAssertEqual(fake.recordedRequests.last?.argument("DesiredVolume"), "0")
    }

    func testSetVolumeSendsExactValueWithinRange() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.setVolume(device, to: 37, transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.argument("DesiredVolume"), "37")
    }

    func testGroupVolumeUsesCoordinatorHostAndGroupRenderingControl() async throws {
        let fake = FakeSOAPTransport()
        fake.responses = [(200, FakeSOAPTransport.envelope("<u:GetGroupVolumeResponse><CurrentVolume>55</CurrentVolume></u:GetGroupVolumeResponse>"))]

        let volume = try await SonosController.groupVolume(group, transport: fake)
        XCTAssertEqual(volume, 55)
        XCTAssertEqual(fake.recordedRequests.first?.soapAction, "\"urn:schemas-upnp-org:service:GroupRenderingControl:1#GetGroupVolume\"")
    }

    func testGroupVolumeReturnsZeroWhenGroupHasNoCoordinator() async throws {
        let leaderless = SonosGroup(id: "g2", coordinatorUUID: "MISSING", members: [device])
        let fake = FakeSOAPTransport()
        let volume = try await SonosController.groupVolume(leaderless, transport: fake)
        XCTAssertEqual(volume, 0)
        XCTAssertTrue(fake.recordedRequests.isEmpty, "Should not make a network call with no coordinator")
    }

    func testIsMutedParsesCurrentMute() async throws {
        let fake = FakeSOAPTransport()
        fake.responses = [(200, FakeSOAPTransport.envelope("<u:GetMuteResponse><CurrentMute>1</CurrentMute></u:GetMuteResponse>"))]
        let muted = try await SonosController.isMuted(device, transport: fake)
        XCTAssertTrue(muted)
    }

    func testSetMuteSendsDesiredMuteAsOneOrZero() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.setMute(device, muted: true, transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.argument("DesiredMute"), "1")

        try await SonosController.setMute(device, muted: false, transport: fake)
        XCTAssertEqual(fake.recordedRequests.last?.argument("DesiredMute"), "0")
    }

    func testSetGroupMuteUsesCoordinatorAndGroupRenderingControl() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.setGroupMute(group, muted: true, transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.url.host, coordinator.host)
        XCTAssertEqual(fake.recordedRequests.first?.soapAction, "\"urn:schemas-upnp-org:service:GroupRenderingControl:1#SetGroupMute\"")
    }
}
