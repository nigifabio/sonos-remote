import XCTest
@testable import SonosRemote

final class SonosPartyModeTests: XCTestCase {
    private let office = SonosDevice(uuid: "A", name: "Office", host: "10.0.0.10")
    private let bedroom = SonosDevice(uuid: "B", name: "Bedroom", host: "10.0.0.11")
    private let kitchen = SonosDevice(uuid: "C", name: "Kitchen", host: "10.0.0.12")
    private let legacy = SonosDevice(uuid: "Z", name: "amelia Room", host: "10.0.0.212")

    private func group(_ id: String, _ members: [SonosDevice], household: String = "S2") -> SonosGroup {
        SonosGroup(id: id, coordinatorUUID: members[0].uuid, members: members, householdID: household)
    }

    func testOnWhenTheOnlyMultiRoomHouseholdIsOneGroup() {
        XCTAssertTrue(SonosPartyMode.isOn([group("g1", [office, bedroom, kitchen])]))
    }

    func testOffWhenAHouseholdIsSplit() {
        XCTAssertFalse(SonosPartyMode.isOn([group("g1", [office, bedroom]), group("g2", [kitchen])]))
    }

    func testOffForASingleRoom() {
        XCTAssertFalse(SonosPartyMode.isOn([group("g1", [office])]))
        XCTAssertFalse(SonosPartyMode.canToggle([group("g1", [office])]))
    }

    /// The bug this replaces: with a one-speaker S1 household next to the
    /// S2 system, "one group overall" could never be true, so Party Mode
    /// never read as on and kept trying to join S1 to S2.
    func testASeparateOneRoomHouseholdDoesNotCount() {
        let groups = [group("g1", [office, bedroom, kitchen]), group("s1", [legacy], household: "S1")]
        XCTAssertTrue(SonosPartyMode.isOn(groups))
        XCTAssertTrue(SonosPartyMode.canToggle(groups))
    }

    func testPlanNeverJoinsAcrossHouseholds() {
        let groups = [group("g1", [office]), group("g2", [bedroom]), group("s1", [legacy], household: "S1")]
        let steps = SonosPartyMode.plan(groups, playingGroupIDs: [], preferredGroupID: nil)
        XCTAssertEqual(steps.count, 1)
        XCTAssertFalse(steps[0].joiners.contains(legacy))
        XCTAssertNotEqual(steps[0].coordinator, legacy)
    }

    func testPlanKeepsThePlayingGroupAsCoordinator() {
        let groups = [group("g1", [office]), group("g2", [bedroom]), group("g3", [kitchen])]
        let steps = SonosPartyMode.plan(groups, playingGroupIDs: ["g2"], preferredGroupID: "g3")
        XCTAssertEqual(steps, [SonosPartyMode.Step(coordinator: bedroom, joiners: [office, kitchen])])
    }

    func testPlanFallsBackToSelectedThenLargest() {
        let groups = [group("g1", [office]), group("g2", [bedroom, kitchen])]
        XCTAssertEqual(SonosPartyMode.plan(groups, playingGroupIDs: [], preferredGroupID: "g1").first?.coordinator, office)
        XCTAssertEqual(SonosPartyMode.plan(groups, playingGroupIDs: [], preferredGroupID: nil).first?.coordinator, bedroom)
    }

    func testPlanIsEmptyWhenAlreadyGrouped() {
        XCTAssertTrue(SonosPartyMode.plan([group("g1", [office, bedroom])], playingGroupIDs: [], preferredGroupID: nil).isEmpty)
    }

    func testRoomsToSplitAreTheNonCoordinators() {
        XCTAssertEqual(SonosPartyMode.roomsToSplit([group("g1", [office, bedroom, kitchen])]), [bedroom, kitchen])
    }
}

final class PlayModeTests: XCTestCase {
    func testEverySonosValueRoundTrips() {
        for value in ["NORMAL", "REPEAT_ALL", "REPEAT_ONE", "SHUFFLE_NOREPEAT", "SHUFFLE", "SHUFFLE_REPEAT_ONE"] {
            XCTAssertEqual(PlayMode(sonosValue: value).sonosValue, value)
        }
    }

    func testShuffleMeansShuffleWithRepeatAll() {
        XCTAssertEqual(PlayMode(sonosValue: "SHUFFLE"), PlayMode(shuffle: true, repeatMode: .all))
        XCTAssertEqual(PlayMode(sonosValue: "SHUFFLE_NOREPEAT"), PlayMode(shuffle: true, repeatMode: .off))
    }

    func testUnknownValueReadsAsNormal() {
        XCTAssertEqual(PlayMode(sonosValue: "SOMETHING_NEW"), PlayMode())
    }

    func testRepeatCyclesOffAllOneAndKeepsShuffle() {
        let start = PlayMode(shuffle: true, repeatMode: .off)
        XCTAssertEqual(start.nextRepeat, PlayMode(shuffle: true, repeatMode: .all))
        XCTAssertEqual(start.nextRepeat.nextRepeat, PlayMode(shuffle: true, repeatMode: .one))
        XCTAssertEqual(start.nextRepeat.nextRepeat.nextRepeat, start)
    }
}
