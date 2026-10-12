import XCTest
@testable import SonosRemote

@MainActor
final class PlaybackHistoryFileTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var directory: URL!
    private var fileURL: URL { directory.appendingPathComponent("nested/history.json") }

    override func setUp() {
        super.setUp()
        suiteName = "PlaybackHistoryFileTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        defaults = nil
        super.tearDown()
    }

    private func readDocument() throws -> PlaybackHistoryFile.Document {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PlaybackHistoryFile.Document.self, from: Data(contentsOf: fileURL))
    }

    func testRecordingATrackWritesItToTheSharedFile() throws {
        let vm = SonosViewModel(defaults: defaults, historyFileURL: fileURL)
        let group = SonosGroup(id: "g1", coordinatorUUID: "A", members: [SonosDevice(uuid: "A", name: "Kitchen", host: "10.0.0.10")])
        var track = TrackInfo()
        track.title = "Angel Of The Morning"
        track.artist = "Juice Newton"
        track.album = "Juice"
        track.sourceURI = "x-sonos-spotify:spotify%3atrack%3aabc"
        vm.recordHistoryIfChanged(group: group, track: track)

        let document = try readDocument()
        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.entries.count, 1)
        let entry = try XCTUnwrap(document.entries.first)
        XCTAssertEqual(entry.room, "Kitchen")
        XCTAssertEqual(entry.title, "Angel Of The Morning")
        XCTAssertEqual(entry.artist, "Juice Newton")
        XCTAssertEqual(entry.service, "Spotify")
        XCTAssertEqual(entry.uri, "x-sonos-spotify:spotify%3atrack%3aabc")
        XCTAssertNil(entry.source)
    }

    /// Other tools read this file, so its field names and date format are a
    /// contract: snake_case keys and ISO 8601 timestamps.
    func testFileUsesStableKeysAndISODates() throws {
        let vm = SonosViewModel(defaults: defaults, historyFileURL: fileURL)
        let group = SonosGroup(id: "g1", coordinatorUUID: "A", members: [SonosDevice(uuid: "A", name: "Kitchen", host: "10.0.0.10")])
        var track = TrackInfo()
        track.title = "Song"
        vm.recordHistoryIfChanged(group: group, track: track)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        let entry = try XCTUnwrap((object["entries"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(entry.keys), ["played_at", "room", "title", "artist", "album", "service"])
        let playedAt = try XCTUnwrap(entry["played_at"] as? String)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: playedAt), "\(playedAt) should be ISO 8601")
    }

    func testAnEmptyFileIsCreatedAtLaunchSoReadersFindOne() throws {
        _ = SonosViewModel(defaults: defaults, historyFileURL: fileURL)
        XCTAssertEqual(try readDocument().entries.count, 0)
    }

    func testNoFileIsWrittenUnlessAURLIsGiven() {
        let vm = SonosViewModel(defaults: defaults)
        let group = SonosGroup(id: "g1", coordinatorUUID: "A", members: [SonosDevice(uuid: "A", name: "Kitchen", host: "10.0.0.10")])
        var track = TrackInfo()
        track.title = "Song"
        vm.recordHistoryIfChanged(group: group, track: track)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testHistorySavedBeforeTheURIFieldStillLoads() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","date":700000000,"groupName":"Kitchen","title":"Old Song","artist":"A","album":"","service":"Spotify"}]
        """
        defaults.set(Data(legacy.utf8), forKey: "playbackHistory")
        let vm = SonosViewModel(defaults: defaults)
        XCTAssertEqual(vm.playbackHistory.first?.title, "Old Song")
        XCTAssertNil(vm.playbackHistory.first?.uri)
    }
}
