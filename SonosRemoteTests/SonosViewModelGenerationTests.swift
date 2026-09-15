import XCTest
@testable import SonosRemote

@MainActor
final class SonosViewModelGenerationTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SonosViewModelGenerationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testNotMixedWithASingleGeneration() {
        let vm = SonosViewModel(defaults: defaults)
        let a = SonosDevice(uuid: "A", name: "Kitchen", host: "10.0.0.10")
        let b = SonosDevice(uuid: "B", name: "Office", host: "10.0.0.11")
        vm.groups = [
            SonosGroup(id: "g1", coordinatorUUID: "A", members: [a]),
            SonosGroup(id: "g2", coordinatorUUID: "B", members: [b]),
        ]
        vm.deviceGenerations = ["A": .s2, "B": .s2]
        XCTAssertFalse(vm.hasMixedGenerations)
    }

    func testNotMixedWhenOtherGenerationIsUnknown() {
        let vm = SonosViewModel(defaults: defaults)
        let a = SonosDevice(uuid: "A", name: "Kitchen", host: "10.0.0.10")
        let b = SonosDevice(uuid: "B", name: "Office", host: "10.0.0.11")
        vm.groups = [
            SonosGroup(id: "g1", coordinatorUUID: "A", members: [a]),
            SonosGroup(id: "g2", coordinatorUUID: "B", members: [b]),
        ]
        vm.deviceGenerations = ["A": .s2, "B": .unknown]
        XCTAssertFalse(vm.hasMixedGenerations)
    }

    func testMixedWhenBothGenerationsPresent() {
        let vm = SonosViewModel(defaults: defaults)
        let a = SonosDevice(uuid: "A", name: "Kitchen", host: "10.0.0.10")
        let b = SonosDevice(uuid: "B", name: "Old Zone Player", host: "10.0.0.11")
        vm.groups = [
            SonosGroup(id: "g1", coordinatorUUID: "A", members: [a]),
            SonosGroup(id: "g2", coordinatorUUID: "B", members: [b]),
        ]
        vm.deviceGenerations = ["A": .s2, "B": .s1]
        XCTAssertTrue(vm.hasMixedGenerations)
    }

    func testGenerationForGroupComesFromCoordinator() {
        let vm = SonosViewModel(defaults: defaults)
        let coordinator = SonosDevice(uuid: "A", name: "Kitchen", host: "10.0.0.10")
        let member = SonosDevice(uuid: "B", name: "Living Room", host: "10.0.0.11")
        let group = SonosGroup(id: "g1", coordinatorUUID: "A", members: [coordinator, member])
        vm.deviceGenerations = ["A": .s1, "B": .unknown]
        XCTAssertEqual(vm.generation(for: group), .s1)
    }
}
