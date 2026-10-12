import XCTest
@testable import SonosRemote

@MainActor
final class AnnouncementTests: XCTestCase {
    private let office = SonosDevice(uuid: "A", name: "Office", host: "10.0.0.10")
    private let bedroom = SonosDevice(uuid: "B", name: "Bedroom", host: "10.0.0.11")
    private let kitchen = SonosDevice(uuid: "C", name: "Kitchen", host: "10.0.0.12")
    private let bath = SonosDevice(uuid: "D", name: "Bagno", host: "10.0.0.13")

    private var groups: [SonosGroup] {
        [SonosGroup(id: "g1", coordinatorUUID: "A", members: [office, bedroom, kitchen]),
         SonosGroup(id: "g2", coordinatorUUID: "D", members: [bath])]
    }

    // MARK: - who the clip is sent to

    func testAFollowerPlaysOnItsOwn() {
        let targets = AnnouncementService.targets(for: [bedroom], in: groups)
        XCTAssertEqual(targets, [AnnouncementService.Target(player: bedroom, rooms: [bedroom])])
    }

    /// A coordinator can't play alone: its group plays what it plays. So it
    /// is sent once, and every room of the group is reported as hearing it.
    func testTheCoordinatorMeansTheWholeGroupSentOnce() {
        let targets = AnnouncementService.targets(for: [office, bedroom], in: groups)
        XCTAssertEqual(targets, [AnnouncementService.Target(player: office, rooms: [office, bedroom, kitchen])])
    }

    func testEveryRoomRequestedSendsOncePerGroup() {
        let targets = AnnouncementService.targets(for: [office, bedroom, kitchen, bath], in: groups)
        XCTAssertEqual(targets.map(\.player), [office, bath])
    }

    func testARoomOutsideAnyKnownGroupStillGetsATarget() {
        let stray = SonosDevice(uuid: "X", name: "Garage", host: "10.0.0.99")
        XCTAssertEqual(AnnouncementService.targets(for: [stray], in: groups).map(\.player), [stray])
    }

    // MARK: - WAV handling

    /// Shaped like what `say` writes: JUNK before fmt, FLLR before data.
    private func paddedWAV(samples: [UInt8]) -> Data {
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)] }
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
        var body: [UInt8] = Array("WAVE".utf8)
        body += Array("JUNK".utf8) + le32(28) + [UInt8](repeating: 0, count: 28)
        body += Array("fmt ".utf8) + le32(16) + le16(1) + le16(1) + le32(44100) + le32(88200) + le16(2) + le16(16)
        body += Array("FLLR".utf8) + le32(8) + [UInt8](repeating: 0, count: 8)
        body += Array("data".utf8) + le32(samples.count) + samples
        return Data(Array("RIFF".utf8) + le32(body.count) + body)
    }

    func testCanonicalWAVDropsPaddingAndKeepsTheSamples() throws {
        let samples: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        let wav = try XCTUnwrap(AnnouncementService.canonicalWAV(from: paddedWAV(samples: samples)))
        XCTAssertEqual(wav.count, 44 + samples.count)
        XCTAssertEqual([UInt8](wav.suffix(samples.count)), samples)
        XCTAssertEqual(wav, IntercomService.makeWAVFile(pcm16: Data(samples), sampleRate: 44100, channels: 1))
    }

    func testCanonicalWAVRejectsWhatIsNotAWAV() {
        XCTAssertNil(AnnouncementService.canonicalWAV(from: Data("not audio".utf8)))
        XCTAssertNil(AnnouncementService.canonicalWAV(from: Data()))
    }

    func testDurationComesFromTheByteRate() {
        let oneSecond = IntercomService.makeWAVFile(pcm16: Data(count: 88200), sampleRate: 44100, channels: 1)
        XCTAssertEqual(AnnouncementService.duration(ofWAV: oneSecond), 1.0, accuracy: 0.001)
    }

    func testSpeechSynthesisProducesAPlayableWAV() async throws {
        let wav = try await AnnouncementService.synthesize("Test")
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav[36..<40], encoding: .ascii), "data", "Bare 44-byte header, audio straight after")
        XCTAssertGreaterThan(AnnouncementService.duration(ofWAV: wav), 0.1)
    }

    // MARK: - control endpoint

    private func makeViewModel() -> SonosViewModel {
        let suite = "AnnouncementTests.\(UUID().uuidString)"
        let vm = SonosViewModel(defaults: UserDefaults(suiteName: suite)!)
        vm.groups = groups
        return vm
    }

    private func json(_ response: LocalHTTPServer.ControlResponse) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: response.json)) as? [String: Any] ?? [:]
    }

    private func post(_ body: String) -> LocalHTTPServer.ControlRequest {
        LocalHTTPServer.ControlRequest(method: "POST", path: "/api/announce", body: Data(body.utf8))
    }

    func testRoomNamesMatchWithoutRegardToCase() {
        let (found, unknown) = ControlAPI.rooms(named: ["office", " BAGNO ", "Attic"], among: [office, bedroom, bath])
        XCTAssertEqual(found, [office, bath])
        XCTAssertEqual(unknown, ["Attic"])
    }

    func testNoRoomNamesMeansEveryRoom() {
        XCTAssertEqual(ControlAPI.rooms(named: nil, among: [office, bath]).found, [office, bath])
        XCTAssertEqual(ControlAPI.rooms(named: [], among: [office, bath]).found, [office, bath])
    }

    func testStatusListsTheRooms() async {
        let response = await ControlAPI.handle(.init(method: "GET", path: "/api/status", body: Data()), viewModel: makeViewModel())
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(json(response)["rooms"] as? [String], ["Bagno", "Bedroom", "Kitchen", "Office"])
    }

    func testAnnounceRejectsBadRequestsBeforeTouchingAnySpeaker() async {
        let vm = makeViewModel()
        let notJSON = await ControlAPI.handle(post("hello"), viewModel: vm)
        XCTAssertEqual(notJSON.status, 400)
        let empty = await ControlAPI.handle(post(#"{"text": "   "}"#), viewModel: vm)
        XCTAssertEqual(empty.status, 400)
        let tooLong = await ControlAPI.handle(post(#"{"text": "\#(String(repeating: "a", count: 501))"}"#), viewModel: vm)
        XCTAssertEqual(tooLong.status, 400)
        let badVolume = await ControlAPI.handle(post(#"{"text": "hi", "volume": 150}"#), viewModel: vm)
        XCTAssertEqual(badVolume.status, 400)
    }

    func testAnnounceToAnUnknownRoomSaysWhichRoomsExist() async {
        let response = await ControlAPI.handle(post(#"{"text": "hi", "rooms": ["Attic"]}"#), viewModel: makeViewModel())
        XCTAssertEqual(response.status, 404)
        XCTAssertEqual(json(response)["error"] as? String, "Unknown room: Attic")
        XCTAssertEqual(json(response)["rooms"] as? [String], ["Bagno", "Bedroom", "Kitchen", "Office"])
    }

    func testUnknownEndpointIs404() async {
        let response = await ControlAPI.handle(.init(method: "GET", path: "/api/nope", body: Data()), viewModel: makeViewModel())
        XCTAssertEqual(response.status, 404)
    }
}
