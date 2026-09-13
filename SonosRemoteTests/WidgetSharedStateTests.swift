import XCTest
@testable import SonosRemote

final class WidgetSharedStateTests: XCTestCase {
    func testWidgetSnapshotRoundTripsThroughJSON() throws {
        let room = WidgetRoomSnapshot(
            id: "RINCON_A", name: "Kitchen", host: "10.0.0.10",
            volume: 42, groupID: "g1", groupCoordinatorUUID: "RINCON_A"
        )
        let nowPlaying = WidgetNowPlaying(title: "Song", artist: "Artist", isPlaying: true)
        let snapshot = WidgetSnapshot(
            rooms: [room], nowPlayingByGroup: ["g1": nowPlaying],
            isPartyMode: false, updatedAt: Date()
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.rooms.count, 1)
        XCTAssertEqual(decoded.rooms.first?.name, "Kitchen")
        XCTAssertEqual(decoded.rooms.first?.volume, 42)
        XCTAssertEqual(decoded.nowPlayingByGroup["g1"]?.title, "Song")
        XCTAssertEqual(decoded.nowPlayingByGroup["g1"]?.isPlaying, true)
        XCTAssertFalse(decoded.isPartyMode)
    }

    func testReadReturnsNilWithoutAppGroupEntitlement() {
        // The unit test bundle has no App Group entitlement, so the shared
        // container can't resolve — read() must fail closed (nil), not crash.
        XCTAssertNil(WidgetSharedStore.read())
    }
}
