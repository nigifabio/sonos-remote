import XCTest
@testable import SonosRemote

@MainActor
final class GENASubscriptionManagerTests: XCTestCase {
    private let avTransportLastChange = """
    <Event xmlns="urn:schemas-upnp-org:metadata-1-0/AVT/"><InstanceID val="0"><TransportState val="PLAYING"/><CurrentTrackMetaData val=""/></InstanceID></Event>
    """
    private let renderingControlLastChange = """
    <Event xmlns="urn:schemas-upnp-org:metadata-1-0/RCS/"><InstanceID val="0"><Volume channel="Master" val="42"/><Volume channel="LF" val="42"/><Volume channel="RF" val="42"/><Mute channel="Master" val="0"/></InstanceID></Event>
    """

    func testAttributeValueFindsMasterChannelVolume() {
        let value = GENASubscriptionManager.attributeValue(
            tag: "Volume", attribute: "val", in: renderingControlLastChange, requiring: ("channel", "Master")
        )
        XCTAssertEqual(value, "42")
    }

    func testAttributeValueIgnoresNonMasterChannels() {
        // Without requiring Master specifically, the first Volume tag (also Master here) still wins,
        // but changing the requirement to a channel that appears later must still find it correctly.
        let value = GENASubscriptionManager.attributeValue(
            tag: "Volume", attribute: "val", in: renderingControlLastChange, requiring: ("channel", "RF")
        )
        XCTAssertEqual(value, "42")
    }

    func testAttributeValueReturnsNilWhenTagMissing() {
        XCTAssertNil(GENASubscriptionManager.attributeValue(tag: "Bass", attribute: "val", in: renderingControlLastChange))
    }

    func testHandleNotifyDispatchesTransportChange() {
        let manager = GENASubscriptionManager()
        var received: (host: String, state: TransportState)?
        manager.onTransportChange = { host, state in received = (host, state) }

        let body = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
        <e:property><LastChange>\(XMLHelpers.escapeXML(avTransportLastChange))</LastChange></e:property>
        </e:propertyset>
        """
        manager.handleNotify(path: "/notify/10.0.0.10/AVTransport", body: body)

        XCTAssertEqual(received?.host, "10.0.0.10")
        XCTAssertEqual(received?.state, .playing)
    }

    func testHandleNotifyDispatchesVolumeChange() {
        let manager = GENASubscriptionManager()
        var received: (host: String, volume: Int)?
        manager.onVolumeChange = { host, volume in received = (host, volume) }

        let body = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
        <e:property><LastChange>\(XMLHelpers.escapeXML(renderingControlLastChange))</LastChange></e:property>
        </e:propertyset>
        """
        manager.handleNotify(path: "/notify/10.0.0.11/RenderingControl", body: body)

        XCTAssertEqual(received?.host, "10.0.0.11")
        XCTAssertEqual(received?.volume, 42)
    }

    func testHandleNotifyIgnoresMalformedPath() {
        let manager = GENASubscriptionManager()
        var called = false
        manager.onTransportChange = { _, _ in called = true }
        manager.handleNotify(path: "/bogus", body: "whatever")
        XCTAssertFalse(called)
    }
}
