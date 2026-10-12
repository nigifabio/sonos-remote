import XCTest
@testable import SonosRemote

@MainActor
final class SonosViewModelTopologyTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    private let office = SonosDevice(uuid: "A", name: "Office", host: "192.0.2.10")
    private let bedroom = SonosDevice(uuid: "B", name: "Bedroom", host: "192.0.2.11")
    private let kitchen = SonosDevice(uuid: "C", name: "Kitchen", host: "192.0.2.12")
    private let legacy = SonosDevice(uuid: "Z", name: "amelia Room", host: "192.0.2.212")

    override func setUp() {
        super.setUp()
        suiteName = "SonosViewModelTopologyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func group(_ id: String, _ members: [SonosDevice], household: String = "A") -> SonosGroup {
        SonosGroup(id: id, coordinatorUUID: members[0].uuid, members: members, householdID: household)
    }

    // MARK: - merging a household's new topology

    /// The bug this guards: re-reading one household replaced the whole
    /// list, so the other household (S1) vanished after any grouping action.
    func testMergingOneHouseholdKeepsTheOther() {
        let current = [group("g1", [office]), group("g2", [bedroom]), group("s1", [legacy], household: "Z")]
        let regrouped = [group("g3", [office, bedroom])]
        let merged = SonosViewModel.merging(regrouped, into: current)
        XCTAssertEqual(merged.map(\.id), ["g3", "s1"])
    }

    func testMergingKeepsTheHouseholdsPlaceInTheList() {
        let current = [group("s1", [legacy], household: "Z"), group("g1", [office, bedroom])]
        let split = [group("g4", [office]), group("g5", [bedroom])]
        XCTAssertEqual(SonosViewModel.merging(split, into: current).map(\.id), ["s1", "g4", "g5"])
    }

    func testMergingAnUnknownHouseholdAppendsIt() {
        let merged = SonosViewModel.merging([group("s1", [legacy], household: "Z")], into: [group("g1", [office])])
        XCTAssertEqual(merged.map(\.id), ["g1", "s1"])
    }

    /// The household ID is its lowest room UUID, so it shifts when that
    /// room leaves; the old groups must still be recognised and replaced.
    func testMergingReplacesAHouseholdWhoseIDShifted() {
        let current = [group("g1", [office, bedroom, kitchen], household: "A")]
        let withoutOffice = [group("g2", [bedroom, kitchen], household: "B")]
        XCTAssertEqual(SonosViewModel.merging(withoutOffice, into: current).map(\.id), ["g2"])
    }

    func testSameTopologyIgnoresOrderOfGroupsAndMembers() {
        let a = [group("g1", [office, bedroom]), group("g2", [kitchen])]
        let b = [group("g2", [kitchen]), SonosGroup(id: "g1", coordinatorUUID: "A", members: [bedroom, office], householdID: "A")]
        XCTAssertTrue(SonosViewModel.sameTopology(a, b))
        XCTAssertFalse(SonosViewModel.sameTopology(a, [group("g1", [office]), group("g2", [kitchen])]))
    }

    func testBootstrapHostsAskUpToTwoSpeakersPerHousehold() {
        let groups = [group("g1", [kitchen, office]), group("g2", [bedroom]), group("s1", [legacy], household: "Z")]
        XCTAssertEqual(SonosViewModel.bootstrapHosts(for: groups), ["192.0.2.10", "192.0.2.11", "192.0.2.212"])
    }

    // MARK: - play position and play mode

    func testPositionAdvancesOnlyWhilePlayingAndStopsAtTheEnd() {
        let vm = SonosViewModel(defaults: defaults)
        let g = group("g1", [office])
        vm.groups = [g]
        var track = TrackInfo()
        track.durationSeconds = 100
        track.positionSeconds = 40
        vm.nowPlaying[g.id] = track
        vm.seek(g, toSeconds: 40) // sets the "read at" anchor to now
        let anchor = Date()

        vm.transportStates[g.id] = .paused
        XCTAssertEqual(vm.position(in: g, at: anchor.addingTimeInterval(30)), 40)

        vm.transportStates[g.id] = .playing
        XCTAssertEqual(vm.position(in: g, at: anchor.addingTimeInterval(30)), 70, accuracy: 1)
        XCTAssertEqual(vm.position(in: g, at: anchor.addingTimeInterval(500)), 100)
    }

    func testPlayModeReportIsAppliedToTheCoordinatorsGroup() {
        let vm = SonosViewModel(defaults: defaults)
        vm.groups = [group("g1", [office, bedroom])]
        vm.applyPlayMode(PlayMode(shuffle: true), fromCoordinatorHost: bedroom.host)
        XCTAssertNil(vm.playModes["g1"])
        vm.applyPlayMode(PlayMode(shuffle: true), fromCoordinatorHost: office.host)
        XCTAssertEqual(vm.playModes["g1"], PlayMode(shuffle: true))
    }

    func testPartyModeStateIsPerHousehold() {
        let vm = SonosViewModel(defaults: defaults)
        vm.groups = [group("g1", [office, bedroom, kitchen]), group("s1", [legacy], household: "Z")]
        XCTAssertTrue(vm.isPartyMode)
        XCTAssertTrue(vm.canTogglePartyMode)
    }

    // MARK: - visible failures

    func testAFailedActionShowsABannerInsteadOfFailingSilently() async {
        let vm = SonosViewModel(defaults: defaults)
        let succeeded = await vm.attempt("Couldn't skip") { throw SOAPError(message: "Next failed on 10.0.0.10: UPnPError", code: 711) }
        XCTAssertFalse(succeeded)
        XCTAssertEqual(vm.banner?.isError, true)
        XCTAssertEqual(vm.banner?.text, "Couldn't skip: the speaker says that isn't possible for what's playing now")
    }

    func testASuccessfulActionShowsNothing() async {
        let vm = SonosViewModel(defaults: defaults)
        let succeeded = await vm.attempt("Couldn't skip") {}
        XCTAssertTrue(succeeded)
        XCTAssertNil(vm.banner)
    }

    func testErrorDescriptionsArePlainLanguage() {
        XCTAssertEqual(SonosViewModel.describe(URLError(.timedOut)), "the speaker didn't answer")
        XCTAssertEqual(SonosViewModel.describe(URLError(.cannotConnectToHost)), "the speaker can't be reached")
        XCTAssertEqual(SonosViewModel.describe(SOAPError(message: "x", code: 402)), "the speaker refused (error 402)")
        XCTAssertEqual(SonosViewModel.describe(SOAPError(message: "Could not determine this Mac's LAN IP address")), "Could not determine this Mac's LAN IP address")
    }

    // MARK: - routine settings

    func testRoutineSettingsDefaultsAndStoredValues() {
        XCTAssertEqual(RoutineSettings(defaults: defaults), RoutineSettings())
        XCTAssertEqual(RoutineSettings().goodnightMinutes, 30)
        XCTAssertNil(RoutineSettings().goodnightMaxVolume)
        XCTAssertTrue(RoutineSettings().movieNightPauseOthers)

        defaults.set(45, forKey: RoutineSettings.goodnightMinutesKey)
        defaults.set(20, forKey: RoutineSettings.goodnightMaxVolumeKey)
        defaults.set(35, forKey: RoutineSettings.movieNightVolumeKey)
        defaults.set(false, forKey: RoutineSettings.movieNightPauseOthersKey)
        let stored = RoutineSettings(defaults: defaults)
        XCTAssertEqual(stored.goodnightMinutes, 45)
        XCTAssertEqual(stored.goodnightMaxVolume, 20)
        XCTAssertEqual(stored.movieNightVolume, 35)
        XCTAssertFalse(stored.movieNightPauseOthers)
    }

    func testSeekBarClock() {
        XCTAssertEqual(SeekBar.clock(0), "0:00")
        XCTAssertEqual(SeekBar.clock(187), "3:07")
        XCTAssertEqual(SeekBar.clock(3723), "1:02:03")
    }
}
