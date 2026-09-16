import XCTest
@testable import SonosRemote

final class SonosControllerEQTests: XCTestCase {
    private let device = SonosDevice(uuid: "RINCON_A01400", name: "Kitchen", host: "10.0.0.50")

    func testGetBassParsesCurrentBass() async throws {
        let fake = FakeSOAPTransport()
        fake.responses = [(200, FakeSOAPTransport.envelope("<u:GetBassResponse><CurrentBass>-3</CurrentBass></u:GetBassResponse>"))]
        let bass = try await SonosController.getBass(device, transport: fake)
        XCTAssertEqual(bass, -3)
    }

    func testSetBassClampsToPlusMinusTen() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.setBass(device, to: 99, transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.argument("DesiredBass"), "10")

        try await SonosController.setBass(device, to: -99, transport: fake)
        XCTAssertEqual(fake.recordedRequests.last?.argument("DesiredBass"), "-10")
    }

    func testGetTrebleParsesCurrentTreble() async throws {
        let fake = FakeSOAPTransport()
        fake.responses = [(200, FakeSOAPTransport.envelope("<u:GetTrebleResponse><CurrentTreble>7</CurrentTreble></u:GetTrebleResponse>"))]
        let treble = try await SonosController.getTreble(device, transport: fake)
        XCTAssertEqual(treble, 7)
    }

    func testSetTrebleClampsToPlusMinusTen() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.setTreble(device, to: 42, transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.argument("DesiredTreble"), "10")
    }

    func testGetLoudnessParsesCurrentLoudness() async throws {
        let fake = FakeSOAPTransport()
        fake.responses = [(200, FakeSOAPTransport.envelope("<u:GetLoudnessResponse><CurrentLoudness>1</CurrentLoudness></u:GetLoudnessResponse>"))]
        let enabled = try await SonosController.getLoudness(device, transport: fake)
        XCTAssertTrue(enabled)
    }

    func testSetLoudnessSendsDesiredLoudnessAsOneOrZero() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.setLoudness(device, enabled: true, transport: fake)
        XCTAssertEqual(fake.recordedRequests.first?.argument("DesiredLoudness"), "1")
    }
}
