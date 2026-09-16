import XCTest
@testable import SonosRemote

final class SonosHouseholdGroupingTests: XCTestCase {
    private let kitchen = SonosDevice(uuid: "A", name: "Kitchen", host: "10.0.0.10")
    private let office = SonosDevice(uuid: "B", name: "Office", host: "10.0.0.11")
    private let legacy = SonosDevice(uuid: "C", name: "amelia Room", host: "10.0.0.212")

    // MARK: - split (sidebar S1/S2 sectioning)

    func testSplitPutsS1DevicesInTheirOwnSection() {
        let generations: [String: SonosSystemGeneration] = ["A": .s2, "B": .s2, "C": .s1]
        let result = SonosHouseholdGrouping.split([kitchen, office, legacy], generations: generations)
        XCTAssertEqual(result.s1.map(\.uuid), ["C"])
        XCTAssertEqual(Set(result.other.map(\.uuid)), ["A", "B"])
    }

    func testSplitTreatsUnknownGenerationAsOtherNotS1() {
        let result = SonosHouseholdGrouping.split([kitchen], generations: ["A": .unknown])
        XCTAssertTrue(result.s1.isEmpty)
        XCTAssertEqual(result.other.map(\.uuid), ["A"])
    }

    func testSplitTreatsMissingGenerationEntryAsOtherNotS1() {
        // No entry at all for "A" (e.g. detectGenerations hasn't finished yet).
        let result = SonosHouseholdGrouping.split([kitchen], generations: [:])
        XCTAssertTrue(result.s1.isEmpty)
        XCTAssertEqual(result.other.map(\.uuid), ["A"])
    }

    func testSplitOfAllS2DevicesLeavesS1Empty() {
        let generations: [String: SonosSystemGeneration] = ["A": .s2, "B": .s2]
        let result = SonosHouseholdGrouping.split([kitchen, office], generations: generations)
        XCTAssertTrue(result.s1.isEmpty)
        XCTAssertEqual(result.other.count, 2)
    }

    // MARK: - pairableGroups (cross-household pairing guard)

    func testPairableGroupsExcludesGroupAlreadyContainingDevice() {
        let group = SonosGroup(id: "g1", coordinatorUUID: "A", members: [kitchen])
        let result = SonosHouseholdGrouping.pairableGroups(for: kitchen, in: [group], generations: ["A": .s2])
        XCTAssertTrue(result.isEmpty)
    }

    func testPairableGroupsExcludesCrossHouseholdGroups() {
        let s2Group = SonosGroup(id: "g1", coordinatorUUID: "A", members: [kitchen])
        let s1Group = SonosGroup(id: "g2", coordinatorUUID: "C", members: [legacy])
        let generations: [String: SonosSystemGeneration] = ["A": .s2, "B": .s2, "C": .s1]
        let result = SonosHouseholdGrouping.pairableGroups(for: office, in: [s2Group, s1Group], generations: generations)
        XCTAssertEqual(result.map(\.id), ["g1"])
    }

    func testPairableGroupsIncludesSameHouseholdGroupNotContainingDevice() {
        let s2Group = SonosGroup(id: "g1", coordinatorUUID: "A", members: [kitchen])
        let generations: [String: SonosSystemGeneration] = ["A": .s2, "B": .s2]
        let result = SonosHouseholdGrouping.pairableGroups(for: office, in: [s2Group], generations: generations)
        XCTAssertEqual(result.map(\.id), ["g1"])
    }

    func testPairableGroupsForUnknownGenerationDeviceOnlyMatchesOtherUnknowns() {
        // Neither side has been classified yet — still shouldn't offer a
        // group we can't be sure is actually the same household.
        let unclassifiedGroup = SonosGroup(id: "g1", coordinatorUUID: "A", members: [kitchen])
        let s2Group = SonosGroup(id: "g2", coordinatorUUID: "B", members: [office])
        let generations: [String: SonosSystemGeneration] = ["B": .s2]
        let result = SonosHouseholdGrouping.pairableGroups(for: legacy, in: [unclassifiedGroup, s2Group], generations: generations)
        XCTAssertEqual(result.map(\.id), ["g1"])
    }
}
