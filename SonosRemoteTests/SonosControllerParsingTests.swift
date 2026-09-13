import XCTest
@testable import SonosRemote

final class SonosControllerParsingTests: XCTestCase {
    /// Shaped like a real (unescaped) ZoneGroupState payload from a Sonos
    /// household with one two-room group and one standalone room.
    private let sampleTopologyXML = """
    <ZoneGroups>
      <ZoneGroup Coordinator="RINCON_KITCHEN01400" ID="RINCON_KITCHEN01400:123">
        <ZoneGroupMember UUID="RINCON_KITCHEN01400" ZoneName="Kitchen" Location="http://10.0.0.10:1400/xml/device_description.xml"/>
        <ZoneGroupMember UUID="RINCON_OFFICE01400" ZoneName="Office" Location="http://10.0.0.11:1400/xml/device_description.xml"/>
      </ZoneGroup>
      <ZoneGroup Coordinator="RINCON_BEDROOM01400" ID="RINCON_BEDROOM01400:456">
        <ZoneGroupMember UUID="RINCON_BEDROOM01400" ZoneName="Bedroom" Location="http://10.0.0.12:1400/xml/device_description.xml"/>
      </ZoneGroup>
    </ZoneGroups>
    """

    func testParsesMultipleGroupsAndMembers() {
        let groups = SonosController.parseZoneGroups(from: sampleTopologyXML)
        XCTAssertEqual(groups.count, 2)

        let kitchenGroup = groups.first { $0.coordinatorUUID == "RINCON_KITCHEN01400" }
        XCTAssertNotNil(kitchenGroup)
        XCTAssertEqual(kitchenGroup?.members.count, 2)
        XCTAssertEqual(Set(kitchenGroup?.members.map(\.name) ?? []), ["Kitchen", "Office"])
        XCTAssertEqual(kitchenGroup?.coordinator?.name, "Kitchen")
        XCTAssertEqual(kitchenGroup?.coordinator?.host, "10.0.0.10")

        let bedroomGroup = groups.first { $0.coordinatorUUID == "RINCON_BEDROOM01400" }
        XCTAssertEqual(bedroomGroup?.members.count, 1)
    }

    func testGroupNameJoinsSortedMemberNames() {
        let groups = SonosController.parseZoneGroups(from: sampleTopologyXML)
        let kitchenGroup = groups.first { $0.coordinatorUUID == "RINCON_KITCHEN01400" }
        XCTAssertEqual(kitchenGroup?.name, "Kitchen + Office")
    }

    func testSkipsInvisibleSatelliteMembers() {
        let xml = """
        <ZoneGroups>
          <ZoneGroup Coordinator="RINCON_MAIN01400" ID="RINCON_MAIN01400:1">
            <ZoneGroupMember UUID="RINCON_MAIN01400" ZoneName="Living Room" Location="http://10.0.0.20:1400/xml/device_description.xml"/>
            <ZoneGroupMember UUID="RINCON_SUB01400" ZoneName="Living Room" Location="http://10.0.0.21:1400/xml/device_description.xml" Invisible="1"/>
          </ZoneGroup>
        </ZoneGroups>
        """
        let groups = SonosController.parseZoneGroups(from: xml)
        XCTAssertEqual(groups.first?.members.count, 1)
        XCTAssertEqual(groups.first?.members.first?.uuid, "RINCON_MAIN01400")
    }

    func testEmptyTopologyReturnsNoGroups() {
        XCTAssertEqual(SonosController.parseZoneGroups(from: "<ZoneGroups></ZoneGroups>").count, 0)
    }

    func testMalformedXMLReturnsNoGroupsWithoutCrashing() {
        XCTAssertEqual(SonosController.parseZoneGroups(from: "not xml at all <<<").count, 0)
    }
}
