import XCTest
@testable import SonosRemote

/// How the view model applies volume reported by the speakers. The main
/// (group) slider used to be overwritten with the coordinator's *own*
/// volume, so in a multi-room group it showed the wrong number from launch
/// and snapped away from wherever it was dragged.
@MainActor
final class SonosViewModelVolumeEventTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    private let office = SonosDevice(uuid: "A", name: "Office", host: "10.0.0.10")
    private let bedroom = SonosDevice(uuid: "B", name: "Bedroom", host: "10.0.0.11")
    private var group: SonosGroup { SonosGroup(id: "g1", coordinatorUUID: "A", members: [office, bedroom]) }

    override func setUp() {
        super.setUp()
        suiteName = "SonosViewModelVolumeEventTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeViewModel() -> SonosViewModel {
        let vm = SonosViewModel(defaults: defaults)
        vm.groups = [group]
        vm.groupVolumes[group.id] = 38
        vm.deviceVolumes = ["A": 34, "B": 40]
        return vm
    }

    func testCoordinatorsOwnVolumeDoesNotOverwriteGroupVolume() {
        let vm = makeViewModel()
        vm.applyDeviceVolume(39, fromHost: office.host)
        XCTAssertEqual(vm.deviceVolumes["A"], 39)
        XCTAssertEqual(vm.groupVolumes[group.id], 38, "Group volume only changes on a group-volume report")
    }

    func testGroupVolumeReportUpdatesGroupOnly() {
        let vm = makeViewModel()
        vm.applyGroupVolume(43, fromCoordinatorHost: office.host)
        XCTAssertEqual(vm.groupVolumes[group.id], 43)
        XCTAssertEqual(vm.deviceVolumes, ["A": 34, "B": 40])
    }

    func testGroupVolumeReportFromANonCoordinatorIsIgnored() {
        let vm = makeViewModel()
        vm.applyGroupVolume(99, fromCoordinatorHost: bedroom.host)
        XCTAssertEqual(vm.groupVolumes[group.id], 38)
    }

    func testMemberVolumeReportUpdatesThatMember() {
        let vm = makeViewModel()
        vm.applyDeviceVolume(55, fromHost: bedroom.host)
        XCTAssertEqual(vm.deviceVolumes["B"], 55)
    }

    func testReportsAreIgnoredRightAfterALocalChange() {
        let vm = makeViewModel()
        vm.groupVolumes[group.id] = 60
        vm.noteLocalVolumeChange(for: group.id)
        vm.applyGroupVolume(38, fromCoordinatorHost: office.host) // stale: sent before our change landed
        XCTAssertEqual(vm.groupVolumes[group.id], 60)

        vm.deviceVolumes["B"] = 70
        vm.noteLocalVolumeChange(for: "B")
        vm.applyDeviceVolume(40, fromHost: bedroom.host)
        XCTAssertEqual(vm.deviceVolumes["B"], 70)
        // A different room is unaffected by that hold.
        vm.applyDeviceVolume(20, fromHost: office.host)
        XCTAssertEqual(vm.deviceVolumes["A"], 20)
    }

    func testMuteReportsUpdateDeviceAndGroupSeparately() {
        let vm = makeViewModel()
        vm.applyDeviceMute(true, fromHost: office.host)
        XCTAssertEqual(vm.deviceMutes["A"], true)
        XCTAssertNil(vm.groupMutes[group.id])

        vm.applyGroupMute(true, fromCoordinatorHost: office.host)
        XCTAssertEqual(vm.groupMutes[group.id], true)
    }
}
