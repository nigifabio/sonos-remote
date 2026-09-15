import XCTest
@testable import SonosRemote

@MainActor
final class SonosViewModelMuteTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SonosViewModelMuteTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testToggleDeviceMuteFlipsLocalStateOptimistically() {
        let vm = SonosViewModel(defaults: defaults)
        let device = SonosDevice(uuid: "A", name: "Kitchen", host: "10.0.0.10")

        XCTAssertNil(vm.deviceMutes[device.uuid])
        vm.toggleDeviceMute(device)
        XCTAssertEqual(vm.deviceMutes[device.uuid], true)
        vm.toggleDeviceMute(device)
        XCTAssertEqual(vm.deviceMutes[device.uuid], false)
    }

    func testToggleGroupMuteFlipsLocalStateOptimistically() {
        let vm = SonosViewModel(defaults: defaults)
        let device = SonosDevice(uuid: "A", name: "Kitchen", host: "10.0.0.10")
        let group = SonosGroup(id: "g1", coordinatorUUID: "A", members: [device])

        XCTAssertNil(vm.groupMutes[group.id])
        vm.toggleGroupMute(group)
        XCTAssertEqual(vm.groupMutes[group.id], true)
        vm.toggleGroupMute(group)
        XCTAssertEqual(vm.groupMutes[group.id], false)
    }
}
