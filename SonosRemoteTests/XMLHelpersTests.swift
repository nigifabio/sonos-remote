import XCTest
@testable import SonosRemote

final class XMLHelpersTests: XCTestCase {
    func testValueOfTagExtractsSimpleContent() {
        let xml = "<CurrentVolume>42</CurrentVolume>"
        XCTAssertEqual(XMLHelpers.value(ofTag: "CurrentVolume", in: xml), "42")
    }

    /// Regression test for a real bug found against live hardware: "upnp:album"
    /// must not match inside "upnp:albumArtURI" just because it's a prefix.
    func testValueOfTagDoesNotMatchTagNamePrefix() {
        let xml = "<upnp:albumArtURI>http://example.com/art.jpg</upnp:albumArtURI>" +
            "<dc:title>All By Myself</dc:title>" +
            "<upnp:album>Falling into You</upnp:album>"
        XCTAssertEqual(XMLHelpers.value(ofTag: "upnp:album", in: xml), "Falling into You")
        XCTAssertEqual(XMLHelpers.value(ofTag: "upnp:albumArtURI", in: xml), "http://example.com/art.jpg")
    }

    func testValueOfTagReturnsNilWhenAbsent() {
        XCTAssertNil(XMLHelpers.value(ofTag: "dc:title", in: "<foo>bar</foo>"))
    }

    func testAttributeValuesParsesSelfClosedTags() {
        let xml = """
        <ZoneGroupMember UUID="RINCON_A" ZoneName="Kitchen" Location="http://10.0.0.5:1400/xml/device_description.xml"/>
        <ZoneGroupMember UUID="RINCON_B" ZoneName="Office" Location="http://10.0.0.6:1400/xml/device_description.xml"/>
        """
        let attrs = XMLHelpers.attributeValues(tag: "ZoneGroupMember", attribute: "UUID", in: xml)
        XCTAssertEqual(attrs.count, 2)
        XCTAssertEqual(attrs[0]["UUID"], "RINCON_A")
        XCTAssertEqual(attrs[0]["ZoneName"], "Kitchen")
        XCTAssertEqual(attrs[1]["ZoneName"], "Office")
    }

    func testEscapeUnescapeRoundTrip() {
        let original = "Title <with> \"quotes\" & 'apostrophes'"
        let escaped = XMLHelpers.escapeXML(original)
        XCTAssertFalse(escaped.contains("<"))
        XCTAssertEqual(XMLHelpers.unescapeXML(escaped), original)
    }

    func testSecondsFromSonosTime() {
        XCTAssertEqual(XMLHelpers.seconds(fromSonosTime: "0:02:35"), 155)
        XCTAssertEqual(XMLHelpers.seconds(fromSonosTime: "1:00:00"), 3600)
        XCTAssertEqual(XMLHelpers.seconds(fromSonosTime: "not-a-time"), 0)
    }
}
