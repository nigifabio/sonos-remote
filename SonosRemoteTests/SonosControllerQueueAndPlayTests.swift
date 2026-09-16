import XCTest
@testable import SonosRemote

final class SonosControllerQueueAndPlayTests: XCTestCase {
    private let device = SonosDevice(uuid: "RINCON_A01400", name: "Kitchen", host: "10.0.0.50")

    // MARK: - Queue management

    func testPlayFromQueueSeeksThenPlays() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.playFromQueue(device, trackNumber: 3, transport: fake)
        XCTAssertEqual(fake.recordedRequests.count, 2)
        XCTAssertEqual(fake.recordedRequests[0].soapAction, "\"urn:schemas-upnp-org:service:AVTransport:1#Seek\"")
        XCTAssertEqual(fake.recordedRequests[0].argument("Unit"), "TRACK_NR")
        XCTAssertEqual(fake.recordedRequests[0].argument("Target"), "3")
        XCTAssertEqual(fake.recordedRequests[1].soapAction, "\"urn:schemas-upnp-org:service:AVTransport:1#Play\"")
    }

    func testRemoveFromQueueTargetsCorrectObjectID() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.removeFromQueue(device, trackNumber: 5, transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.argument("ObjectID"), "Q:0/5")
    }

    func testClearQueueSendsRemoveAllTracksFromQueue() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.clearQueue(device, transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.soapAction, "\"urn:schemas-upnp-org:service:AVTransport:1#RemoveAllTracksFromQueue\"")
    }

    func testReorderQueueSendsFromAndToIndices() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.reorderQueue(device, fromTrackNumber: 2, toTrackNumber: 5, transport: fake)
        let request = try XCTUnwrap(fake.recordedRequests.first)
        XCTAssertEqual(request.argument("StartingIndex"), "2")
        XCTAssertEqual(request.argument("InsertBefore"), "5")
    }

    // MARK: - play(item:on:) — Favorite vs container

    private func item(isContainer: Bool) -> BrowseItem {
        BrowseItem(id: "id1", parentID: "root", title: "Test", subtitle: "", uri: "http://example.com/track.mp3",
                   metadata: "<DIDL-Lite/>", albumArtURL: nil, isContainer: isContainer)
    }

    func testPlayingALeafItemSetsURIDirectlyThenPlays() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.play(item(isContainer: false), on: device, transport: fake)
        XCTAssertEqual(fake.recordedRequests.count, 2)
        XCTAssertEqual(fake.recordedRequests[0].soapAction, "\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"")
        XCTAssertEqual(fake.recordedRequests[0].argument("CurrentURI"), "http://example.com/track.mp3")
        XCTAssertEqual(fake.recordedRequests[1].soapAction, "\"urn:schemas-upnp-org:service:AVTransport:1#Play\"")
    }

    func testPlayingAContainerClearsQueueThenEnqueuesThenPointsAtQueue() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.play(item(isContainer: true), on: device, transport: fake)
        let actions = fake.recordedRequests.compactMap(\.soapAction)
        XCTAssertEqual(actions, [
            "\"urn:schemas-upnp-org:service:AVTransport:1#RemoveAllTracksFromQueue\"",
            "\"urn:schemas-upnp-org:service:AVTransport:1#AddURIToQueue\"",
            "\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"",
            "\"urn:schemas-upnp-org:service:AVTransport:1#Play\""
        ])
        XCTAssertEqual(fake.recordedRequests[2].argument("CurrentURI"), "x-rincon-queue:\(device.uuid)#0")
    }

    // MARK: - playQueue (local-library "play all")

    func testPlayQueueDoesNothingForEmptyItems() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.playQueue([], on: device, transport: fake)
        XCTAssertTrue(fake.recordedRequests.isEmpty)
    }

    func testPlayQueueClearsThenEnqueuesEachItemInOrderThenPlays() async throws {
        let fake = FakeSOAPTransport()
        let items = [
            BrowseItem(id: "1", parentID: "", title: "One", subtitle: "", uri: "http://x/1.mp3", metadata: "<m1/>", albumArtURL: nil, isContainer: false),
            BrowseItem(id: "2", parentID: "", title: "Two", subtitle: "", uri: "http://x/2.mp3", metadata: "<m2/>", albumArtURL: nil, isContainer: false)
        ]
        try await SonosController.playQueue(items, on: device, transport: fake)

        let actions = fake.recordedRequests.compactMap(\.soapAction)
        XCTAssertEqual(actions, [
            "\"urn:schemas-upnp-org:service:AVTransport:1#RemoveAllTracksFromQueue\"",
            "\"urn:schemas-upnp-org:service:AVTransport:1#AddURIToQueue\"",
            "\"urn:schemas-upnp-org:service:AVTransport:1#AddURIToQueue\"",
            "\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"",
            "\"urn:schemas-upnp-org:service:AVTransport:1#Play\""
        ])
        // Order preserved: track "1" enqueued before track "2".
        XCTAssertEqual(fake.recordedRequests[1].argument("EnqueuedURI"), "http://x/1.mp3")
        XCTAssertEqual(fake.recordedRequests[2].argument("EnqueuedURI"), "http://x/2.mp3")
    }

    // MARK: - Grouping

    func testJoinPointsDeviceAtCoordinatorViaRinconURI() async throws {
        let fake = FakeSOAPTransport()
        let coordinator = SonosDevice(uuid: "RINCON_COORD01400", name: "Office", host: "10.0.0.60")
        try await SonosController.join(device, toCoordinator: coordinator, transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.argument("CurrentURI"), "x-rincon:RINCON_COORD01400")
    }

    func testUnjoinSendsBecomeCoordinatorOfStandaloneGroup() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.unjoin(device, transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.soapAction, "\"urn:schemas-upnp-org:service:AVTransport:1#BecomeCoordinatorOfStandaloneGroup\"")
    }

    func testPartyModeJoinsEveryDeviceExceptTheCoordinatorItself() async throws {
        let fake = FakeSOAPTransport()
        let coordinator = SonosDevice(uuid: "RINCON_COORD01400", name: "Office", host: "10.0.0.60")
        let other1 = SonosDevice(uuid: "RINCON_A01400", name: "Kitchen", host: "10.0.0.50")
        let other2 = SonosDevice(uuid: "RINCON_B01400", name: "Bedroom", host: "10.0.0.51")

        await SonosController.partyMode(allDevices: [coordinator, other1, other2], coordinator: coordinator, transport: fake)

        XCTAssertEqual(fake.recordedRequests.count, 2, "Coordinator should not be joined to itself")
        let hosts = Set(fake.recordedRequests.map { $0.url.host })
        XCTAssertEqual(hosts, ["10.0.0.50", "10.0.0.51"])
    }

    func testUngroupAllUnjoinsNonCoordinatorMembersOnly() async throws {
        let fake = FakeSOAPTransport()
        let coordinator = SonosDevice(uuid: "RINCON_COORD01400", name: "Office", host: "10.0.0.60")
        let member = SonosDevice(uuid: "RINCON_A01400", name: "Kitchen", host: "10.0.0.50")
        let group = SonosGroup(id: "g1", coordinatorUUID: coordinator.uuid, members: [coordinator, member])

        await SonosController.ungroupAll([group], transport: fake)

        XCTAssertEqual(fake.recordedRequests.count, 1, "Coordinator is already standalone-capable; only the member should be unjoined")
        XCTAssertEqual(fake.recordedRequests.first?.url.host, "10.0.0.50")
    }
}
