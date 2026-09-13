import XCTest
@testable import SonosRemote

@MainActor
final class SonosViewModelHistoryTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "playbackHistory")
        super.tearDown()
    }

    private func makeGroup() -> SonosGroup {
        let device = SonosDevice(uuid: "A", name: "Kitchen", host: "10.0.0.10")
        return SonosGroup(id: "g1", coordinatorUUID: "A", members: [device])
    }

    func testRecordsNewTrackToHistory() {
        let vm = SonosViewModel()
        let group = makeGroup()
        var track = TrackInfo()
        track.title = "Angel Of The Morning"
        track.artist = "Juice Newton"
        track.sourceURI = "x-sonos-spotify:spotify%3atrack%3aabc"

        vm.recordHistoryIfChanged(group: group, track: track)

        XCTAssertEqual(vm.playbackHistory.count, 1)
        XCTAssertEqual(vm.lastPlayed?.title, "Angel Of The Morning")
        XCTAssertEqual(vm.lastPlayed?.service, .spotify)
    }

    func testDoesNotDuplicateSameTrack() {
        let vm = SonosViewModel()
        let group = makeGroup()
        var track = TrackInfo()
        track.title = "Song A"
        track.artist = "Artist A"

        vm.recordHistoryIfChanged(group: group, track: track)
        vm.recordHistoryIfChanged(group: group, track: track) // same track again, e.g. next poll tick

        XCTAssertEqual(vm.playbackHistory.count, 1)
    }

    func testRecordsAgainWhenTrackChanges() {
        let vm = SonosViewModel()
        let group = makeGroup()
        var trackA = TrackInfo(); trackA.title = "Song A"; trackA.artist = "Artist A"
        var trackB = TrackInfo(); trackB.title = "Song B"; trackB.artist = "Artist B"

        vm.recordHistoryIfChanged(group: group, track: trackA)
        vm.recordHistoryIfChanged(group: group, track: trackB)

        XCTAssertEqual(vm.playbackHistory.count, 2)
        XCTAssertEqual(vm.lastPlayed?.title, "Song B") // newest first
    }

    func testIgnoresEmptyTitle() {
        let vm = SonosViewModel()
        vm.recordHistoryIfChanged(group: makeGroup(), track: TrackInfo())
        XCTAssertTrue(vm.playbackHistory.isEmpty)
    }

    func testLastSpotifyPlaylistRequiresKnownSourceLabel() {
        let vm = SonosViewModel()
        let group = makeGroup()
        var track = TrackInfo()
        track.title = "Random Spotify Track"
        track.artist = "Someone"
        track.sourceURI = "x-sonos-spotify:spotify%3atrack%3axyz"

        // Observed as a track change (e.g. started from the official Sonos app) — we don't know the playlist.
        vm.recordHistoryIfChanged(group: group, track: track)

        XCTAssertNil(vm.lastSpotifyPlaylist)
        XCTAssertEqual(vm.lastSpotifyTrack?.title, "Random Spotify Track")
    }

    func testHistoryIsCappedAtFiftyEntries() {
        let vm = SonosViewModel()
        let group = makeGroup()
        for i in 0..<60 {
            var track = TrackInfo()
            track.title = "Song \(i)"
            track.artist = "Artist"
            vm.recordHistoryIfChanged(group: group, track: track)
        }
        XCTAssertEqual(vm.playbackHistory.count, 50)
        XCTAssertEqual(vm.lastPlayed?.title, "Song 59")
    }
}
