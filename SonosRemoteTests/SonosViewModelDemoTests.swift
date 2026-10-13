import XCTest
@testable import SonosRemote

/// Demo mode shows sample rooms and must never reach the network: it is
/// what the README screenshots are taken from, and what someone without a
/// Sonos system sees.
@MainActor
final class SonosViewModelDemoTests: XCTestCase {
    func testDemoHasASampleHouseholdWithBothGenerations() {
        let vm = SonosViewModel.demo()
        XCTAssertTrue(vm.isDemo)
        XCTAssertEqual(vm.allDevicesSorted.map(\.name), ["Bedroom", "Garage", "Kitchen", "Living Room", "Office", "Patio"])
        XCTAssertTrue(vm.hasMixedGenerations)
        XCTAssertEqual(vm.tvRooms.map(\.name), ["Living Room"])
        XCTAssertEqual(vm.selectedGroup?.members.count, 3)
        XCTAssertEqual(vm.lastPlayed?.title, "Slow Coastline")
    }

    func testDemoNeverStartsDiscoveryOrRunsNetworkActions() async {
        let vm = SonosViewModel.demo()
        XCTAssertFalse(vm.start(), "start() must be a no-op in demo mode")

        var ran = false
        let reported = await vm.attempt("Couldn't do it") { ran = true }
        XCTAssertTrue(reported)
        XCTAssertFalse(ran, "The action itself must not run")
        XCTAssertNil(vm.banner)

        let before = vm.groups
        await vm.refreshTopology()
        let changed = await vm.refreshKnownTopology()
        XCTAssertFalse(changed)
        XCTAssertEqual(vm.groups, before)
    }

    func testDemoControlsStillRespondLocally() throws {
        let vm = SonosViewModel.demo()
        let group = try XCTUnwrap(vm.selectedGroup)
        XCTAssertEqual(vm.transportStates[group.id], .playing)

        vm.togglePlayPause(group)
        XCTAssertEqual(vm.transportStates[group.id], .paused)

        vm.setGroupVolume(group, to: 50)
        XCTAssertEqual(vm.groupVolumes[group.id], 50)

        vm.toggleShuffle(group)
        XCTAssertEqual(vm.playModes[group.id]?.shuffle, false)

        vm.pauseAll()
        XCTAssertTrue(vm.playingGroups.isEmpty)
    }

    func testDemoPlaysDoNotTouchTheRealHistory() {
        let real = UserDefaults.standard.data(forKey: "playbackHistory")
        _ = SonosViewModel.demo()
        XCTAssertEqual(UserDefaults.standard.data(forKey: "playbackHistory"), real)
    }

    func testDemoLibraryAndQueueHaveContent() throws {
        let vm = SonosViewModel.demo()
        XCTAssertFalse(vm.demoLibraryItems(root: "Favorites", container: nil).isEmpty)
        let playlist = try XCTUnwrap(vm.demoLibraryItems(root: "Playlists", container: nil).first)
        XCTAssertTrue(playlist.isContainer)
        XCTAssertFalse(vm.demoLibraryItems(root: "Playlists", container: playlist).contains { $0.isContainer })
        XCTAssertEqual(vm.demoQueue.count, 6)
    }
}
