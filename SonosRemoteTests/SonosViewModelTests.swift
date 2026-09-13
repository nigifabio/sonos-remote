import XCTest
@testable import SonosRemote

@MainActor
final class SonosViewModelTests: XCTestCase {
    private func makeDevice(_ uuid: String, _ name: String) -> SonosDevice {
        SonosDevice(uuid: uuid, name: name, host: "10.0.0.\(uuid.hashValue % 200 + 10)")
    }

    func testIsPartyModeTrueOnlyForSingleMultiMemberGroup() {
        let vm = SonosViewModel()
        let kitchen = makeDevice("A", "Kitchen")
        let office = makeDevice("B", "Office")

        vm.groups = [SonosGroup(id: "g1", coordinatorUUID: "A", members: [kitchen, office])]
        XCTAssertTrue(vm.isPartyMode)

        vm.groups = [
            SonosGroup(id: "g1", coordinatorUUID: "A", members: [kitchen]),
            SonosGroup(id: "g2", coordinatorUUID: "B", members: [office]),
        ]
        XCTAssertFalse(vm.isPartyMode)
    }

    func testGroupContainingFindsTheRightGroup() {
        let vm = SonosViewModel()
        let kitchen = makeDevice("A", "Kitchen")
        let bedroom = makeDevice("C", "Bedroom")
        let group1 = SonosGroup(id: "g1", coordinatorUUID: "A", members: [kitchen])
        let group2 = SonosGroup(id: "g2", coordinatorUUID: "C", members: [bedroom])
        vm.groups = [group1, group2]

        XCTAssertEqual(vm.group(containing: kitchen)?.id, "g1")
        XCTAssertEqual(vm.group(containing: bedroom)?.id, "g2")
    }

    func testTrackInfoForDeviceReadsItsGroupsNowPlaying() {
        let vm = SonosViewModel()
        let kitchen = makeDevice("A", "Kitchen")
        let group = SonosGroup(id: "g1", coordinatorUUID: "A", members: [kitchen])
        vm.groups = [group]

        var track = TrackInfo()
        track.title = "Test Song"
        vm.nowPlaying["g1"] = track

        XCTAssertEqual(vm.trackInfo(for: kitchen)?.title, "Test Song")
    }

    func testAllDevicesSortedIsAlphabetical() {
        let vm = SonosViewModel()
        vm.groups = [
            SonosGroup(id: "g1", coordinatorUUID: "C", members: [makeDevice("C", "Zebra Room")]),
            SonosGroup(id: "g2", coordinatorUUID: "A", members: [makeDevice("A", "Attic")]),
        ]
        XCTAssertEqual(vm.allDevicesSorted.map(\.name), ["Attic", "Zebra Room"])
    }

    func testSelectedGroupFallsBackToFirstWhenSelectionIsStale() {
        let vm = SonosViewModel()
        let device = makeDevice("A", "Kitchen")
        vm.groups = [SonosGroup(id: "g1", coordinatorUUID: "A", members: [device])]
        vm.selectedGroupID = "does-not-exist"
        XCTAssertEqual(vm.selectedGroup?.id, "g1")
    }
}
