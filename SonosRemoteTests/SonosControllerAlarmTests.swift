import XCTest
@testable import SonosRemote

final class SonosControllerAlarmTests: XCTestCase {
    private let device = SonosDevice(uuid: "RINCON_A01400", name: "Kitchen", host: "10.0.0.50")

    private let alarm = SonosAlarm(
        id: "5", startTime: "07:30:00", duration: "00:30:00", recurrence: "DAILY",
        enabled: true, roomUUID: "RINCON_A01400", programURI: "x-rincon-buzzer:0",
        programMetaData: "", playMode: "NORMAL", volume: 40, includeLinkedZones: false
    )

    func testListAlarmsParsesAttributesFromCurrentAlarmList() async throws {
        let fake = FakeSOAPTransport()
        let list = """
        &lt;Alarms&gt;&lt;Alarm ID="5" StartTime="07:30:00" Duration="00:30:00" Recurrence="DAILY" Enabled="1" RoomUUID="RINCON_A01400" ProgramURI="x-rincon-buzzer:0" ProgramMetaData="" PlayMode="NORMAL" Volume="40" IncludeLinkedZones="0"/&gt;&lt;/Alarms&gt;
        """
        fake.responses = [(200, FakeSOAPTransport.envelope("<u:ListAlarmsResponse><CurrentAlarmList>\(list)</CurrentAlarmList></u:ListAlarmsResponse>"))]

        let alarms = try await SonosController.listAlarms(device, transport: fake)
        XCTAssertEqual(alarms.count, 1)
        XCTAssertEqual(alarms.first?.id, "5")
        XCTAssertEqual(alarms.first?.startTime, "07:30:00")
        XCTAssertEqual(alarms.first?.volume, 40)
        XCTAssertTrue(alarms.first?.enabled ?? false)
    }

    func testListAlarmsReturnsEmptyWhenNoAlarms() async throws {
        let fake = FakeSOAPTransport()
        fake.responses = [(200, FakeSOAPTransport.envelope("<u:ListAlarmsResponse><CurrentAlarmList>&lt;Alarms/&gt;</CurrentAlarmList></u:ListAlarmsResponse>"))]
        let alarms = try await SonosController.listAlarms(device, transport: fake)
        XCTAssertTrue(alarms.isEmpty)
    }

    func testCreateAlarmDefaultsToBuiltInChime() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.createAlarm(device: device, startTime: "06:00:00", transport: fake)
        let request = try XCTUnwrap(fake.recordedRequests.first)
        XCTAssertEqual(request.argument("ProgramURI"), "x-rincon-buzzer:0")
        XCTAssertEqual(request.argument("StartLocalTime"), "06:00:00")
        XCTAssertEqual(request.argument("RoomUUID"), device.uuid)
    }

    func testUpdateAlarmSendsAllAlarmFields() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.updateAlarm(alarm, on: device, transport: fake)
        let request = try XCTUnwrap(fake.recordedRequests.first)
        XCTAssertEqual(request.argument("ID"), "5")
        XCTAssertEqual(request.argument("Volume"), "40")
        XCTAssertEqual(request.argument("Enabled"), "1")
    }

    func testSetAlarmEnabledFalseOnlyFlipsEnabledFlag() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.setAlarmEnabled(alarm, enabled: false, on: device, transport: fake)
        let request = try XCTUnwrap(fake.recordedRequests.first)
        XCTAssertEqual(request.argument("Enabled"), "0")
        XCTAssertEqual(request.argument("ID"), "5") // rest of the alarm unchanged
        XCTAssertEqual(request.argument("Volume"), "40")
    }

    func testDeleteAlarmSendsDestroyAlarmWithID() async throws {
        let fake = FakeSOAPTransport()
        try await SonosController.deleteAlarm(alarm, on: device, transport: fake)
        let request = try XCTUnwrap(fake.recordedRequests.first)
        XCTAssertEqual(request.soapAction, "\"urn:schemas-upnp-org:service:AlarmClock:1#DestroyAlarm\"")
        XCTAssertEqual(request.argument("ID"), "5")
    }
}
