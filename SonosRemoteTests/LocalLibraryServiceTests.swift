import XCTest
@testable import SonosRemote

final class LocalLibraryServiceTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
        super.tearDown()
    }

    private func touch(_ relativePath: String, isDirectory: Bool = false) {
        let url = tempRoot.appendingPathComponent(relativePath)
        if isDirectory {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
    }

    func testListsFoldersBeforeFilesAlphabetically() {
        touch("Zebra.mp3")
        touch("Albums", isDirectory: true)
        touch("Apple.mp3")

        let items = LocalLibraryService.list(root: tempRoot, relativePath: "")
        XCTAssertEqual(items.map(\.title), ["Albums", "Apple", "Zebra"])
        XCTAssertTrue(items[0].isContainer)
        XCTAssertFalse(items[1].isContainer)
        XCTAssertFalse(items[2].isContainer)
    }

    func testSkipsUnsupportedFileTypesAndHiddenFiles() {
        touch("notes.txt")
        touch(".DS_Store")
        touch("song.mp3")

        let items = LocalLibraryService.list(root: tempRoot, relativePath: "")
        XCTAssertEqual(items.map(\.title), ["song"])
    }

    func testFileTitleStripsExtensionButKeepsFullNameAsID() {
        touch("Track One.flac")

        let items = LocalLibraryService.list(root: tempRoot, relativePath: "")
        XCTAssertEqual(items.first?.title, "Track One")
        XCTAssertEqual(items.first?.id, "Track One.flac")
    }

    func testListsSubfolderContentsByRelativePath() {
        touch("Album/track1.mp3")
        touch("Album/track2.mp3")

        let items = LocalLibraryService.list(root: tempRoot, relativePath: "Album")
        XCTAssertEqual(items.map(\.title).sorted(), ["track1", "track2"])
        XCTAssertTrue(items.allSatisfy { $0.id.hasPrefix("Album/") })
    }

    func testFilesReturnsOnlyNonContainerEntries() {
        touch("Album/track1.mp3")
        touch("Album/Artwork", isDirectory: true)

        let files = LocalLibraryService.files(root: tempRoot, relativePath: "Album")
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.title, "track1")
    }

    func testContentTypeMapping() {
        XCTAssertEqual(LocalLibraryService.contentType(forExtension: "mp3"), "audio/mpeg")
        XCTAssertEqual(LocalLibraryService.contentType(forExtension: "FLAC"), "audio/flac")
        XCTAssertEqual(LocalLibraryService.contentType(forExtension: "xyz"), "application/octet-stream")
    }

    func testTrackURLBuildsPercentEncodedLibraryPath() {
        let url = LocalLibraryService.trackURL(ip: "10.0.0.5", relativePath: "My Album/Track One.mp3")
        XCTAssertEqual(url?.host, "10.0.0.5")
        XCTAssertEqual(url?.port, 57123)
        XCTAssertEqual(url?.path, "/library/My Album/Track One.mp3")
    }
}
