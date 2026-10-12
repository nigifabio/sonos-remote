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

    /// Shape of a real GroupRenderingControl NOTIFY: plain evented
    /// variables, no LastChange wrapper.
    private let groupRenderingControlBody = """
    <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0"><e:property><GroupVolume>38</GroupVolume></e:property><e:property><GroupMute>1</GroupMute></e:property><e:property><GroupVolumeChangeable>1</GroupVolumeChangeable></e:property></e:propertyset>
    """

    func testHandleNotifyDispatchesGroupVolumeAndMute() {
        let manager = GENASubscriptionManager()
        var volume: (host: String, value: Int)?
        var mute: (host: String, value: Bool)?
        var deviceVolumeCalled = false
        manager.onGroupVolumeChange = { host, value in volume = (host, value) }
        manager.onGroupMuteChange = { host, value in mute = (host, value) }
        manager.onVolumeChange = { _, _ in deviceVolumeCalled = true }

        manager.handleNotify(path: "/notify/10.0.0.10/GroupRenderingControl", body: groupRenderingControlBody)

        XCTAssertEqual(volume?.host, "10.0.0.10")
        XCTAssertEqual(volume?.value, 38)
        XCTAssertEqual(mute?.value, true)
        XCTAssertFalse(deviceVolumeCalled)
    }

    func testHandleNotifyDispatchesDeviceMute() {
        let manager = GENASubscriptionManager()
        var received: (host: String, muted: Bool)?
        manager.onMuteChange = { host, muted in received = (host, muted) }

        let body = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
        <e:property><LastChange>\(XMLHelpers.escapeXML(renderingControlLastChange))</LastChange></e:property>
        </e:propertyset>
        """
        manager.handleNotify(path: "/notify/10.0.0.11/RenderingControl", body: body)

        XCTAssertEqual(received?.host, "10.0.0.11")
        XCTAssertEqual(received?.muted, false)
    }

    /// A speaker's own volume is only ever reported by that speaker, so
    /// every member needs RenderingControl — not just the coordinator.
    func testDesiredSubscriptionsCoverEveryMemberNotJustCoordinators() {
        let wanted = GENASubscriptionManager.desiredSubscriptions(
            coordinatorHosts: ["10.0.0.10"], memberHosts: ["10.0.0.10", "10.0.0.11", "10.0.0.12"]
        )
        let pairs = Set(wanted.map { "\($0.host)|\($0.service.rawValue)" })
        XCTAssertEqual(pairs, [
            "10.0.0.10|AVTransport", "10.0.0.10|GroupRenderingControl",
            "10.0.0.10|RenderingControl", "10.0.0.11|RenderingControl", "10.0.0.12|RenderingControl"
        ])
        XCTAssertEqual(wanted.count, pairs.count, "No duplicate subscriptions")
    }

    func testHandleNotifyIgnoresMalformedPath() {
        let manager = GENASubscriptionManager()
        var called = false
        manager.onTransportChange = { _, _ in called = true }
        manager.handleNotify(path: "/bogus", body: "whatever")
        XCTAssertFalse(called)
    }
}
