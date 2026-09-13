import XCTest
@testable import SonosRemote

final class DIDLParserTests: XCTestCase {
    func testParsesItemWithResourceAndArt() {
        let didl = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
        <item id="Q:0/1" parentID="Q:0" restricted="1">
        <dc:title>Test Track</dc:title>
        <dc:creator>Test Artist</dc:creator>
        <res protocolInfo="sonos.com-spotify">http://example.com/track?a=1&amp;b=2</res>
        <upnp:albumArtURI>/getaa?u=1</upnp:albumArtURI>
        <upnp:class>object.item.audioItem.musicTrack</upnp:class>
        </item>
        </DIDL-Lite>
        """
        let items = DIDLParser.parseItems(from: didl, host: "10.0.0.10")
        XCTAssertEqual(items.count, 1)
        let item = items[0]
        XCTAssertEqual(item.id, "Q:0/1")
        XCTAssertEqual(item.parentID, "Q:0")
        XCTAssertEqual(item.title, "Test Track")
        XCTAssertEqual(item.subtitle, "Test Artist")
        XCTAssertEqual(item.uri, "http://example.com/track?a=1&b=2") // unescaped once for direct use
        XCTAssertFalse(item.isContainer)
        XCTAssertEqual(item.albumArtURL?.absoluteString, "http://10.0.0.10:1400/getaa?u=1")
        XCTAssertTrue(item.metadata.contains("<DIDL-Lite"))
        XCTAssertTrue(item.metadata.contains("Test Track"))
    }

    /// Regression test: caught live on the iOS app when an album named
    /// "Juice Newton's Greatest Hits" showed up as literal
    /// "Juice Newton&apos;s Greatest Hits" — title/creator weren't unescaped.
    func testTitleAndSubtitleAreUnescaped() {
        let didl = """
        <DIDL-Lite>
        <item id="Q:0/1" parentID="Q:0">
        <dc:title>Rock &amp; Roll Ain&apos;t Dead</dc:title>
        <dc:creator>AC&amp;DC</dc:creator>
        </item>
        </DIDL-Lite>
        """
        let items = DIDLParser.parseItems(from: didl, host: "10.0.0.10")
        XCTAssertEqual(items[0].title, "Rock & Roll Ain't Dead")
        XCTAssertEqual(items[0].subtitle, "AC&DC")
    }

    func testParsesContainerDistinctFromItem() {
        let didl = """
        <DIDL-Lite>
        <container id="SQ:1" parentID="SQ:" restricted="1">
        <dc:title>My Playlist</dc:title>
        <res>file:///jffs/settings/savedqueues.rsq#1</res>
        </container>
        </DIDL-Lite>
        """
        let items = DIDLParser.parseItems(from: didl, host: "10.0.0.10")
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isContainer)
        XCTAssertEqual(items[0].title, "My Playlist")
    }

    func testPreservesDocumentOrderAcrossItemsAndContainers() {
        let didl = """
        <DIDL-Lite>
        <container id="A:ALBUM/1" parentID="A:ALBUM"><dc:title>Album One</dc:title></container>
        <item id="A:TRACK/1" parentID="A:TRACK"><dc:title>Track One</dc:title></item>
        <container id="A:ALBUM/2" parentID="A:ALBUM"><dc:title>Album Two</dc:title></container>
        </DIDL-Lite>
        """
        let items = DIDLParser.parseItems(from: didl, host: "10.0.0.10")
        XCTAssertEqual(items.map(\.title), ["Album One", "Track One", "Album Two"])
    }

    func testMissingResourceOrArtDoesNotCrash() {
        let didl = """
        <DIDL-Lite>
        <item id="FV:2/1" parentID="FV:2"><dc:title>Discover Sonos Radio</dc:title></item>
        </DIDL-Lite>
        """
        let items = DIDLParser.parseItems(from: didl, host: "10.0.0.10")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].uri, "")
        XCTAssertNil(items[0].albumArtURL)
    }

    func testAbsoluteArtURLIsKeptAsIs() {
        let didl = """
        <DIDL-Lite>
        <item id="FV:2/1" parentID="FV:2">
        <dc:title>Radio Station</dc:title>
        <upnp:albumArtURI>http://cdn.example.com/art.png</upnp:albumArtURI>
        </item>
        </DIDL-Lite>
        """
        let items = DIDLParser.parseItems(from: didl, host: "10.0.0.10")
        XCTAssertEqual(items[0].albumArtURL?.absoluteString, "http://cdn.example.com/art.png")
    }

    func testItemsWithoutIDAreSkipped() {
        let didl = "<DIDL-Lite><item><dc:title>No ID</dc:title></item></DIDL-Lite>"
        XCTAssertEqual(DIDLParser.parseItems(from: didl, host: "10.0.0.10").count, 0)
    }
}
