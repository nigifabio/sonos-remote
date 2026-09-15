import Foundation

/// Manages GENA (UPnP eventing) subscriptions for the devices we care about
/// — renews them before they expire, and parses incoming NOTIFY bodies into
/// plain state changes for `SonosViewModel` to apply immediately.
@MainActor
final class GENASubscriptionManager {
    static let shared = GENASubscriptionManager()

    private struct Subscription {
        var sid: String
        var host: String
        var service: SonosService
        var renewTask: Task<Void, Never>?
    }

    private var subscriptions: [String: Subscription] = [:] // key: "\(host)|\(service.rawValue)"
    private var started = false

    var onTransportChange: ((_ host: String, _ state: TransportState) -> Void)?
    var onVolumeChange: ((_ host: String, _ volume: Int) -> Void)?

    func start() {
        guard !started else { return }
        started = true
        try? GENAEventServer.shared.start()
        GENAEventServer.shared.onNotify = { [weak self] path, body in
            guard let self else { return }
            Task { @MainActor in self.handleNotify(path: path, body: body) }
        }
    }

    /// Ensures exactly these coordinator hosts have active subscriptions;
    /// drops any for hosts no longer in the list (a room left/joined a group).
    func updateSubscriptions(coordinatorHosts: [String]) async {
        let desired = Set(coordinatorHosts.flatMap { host in
            [key(host: host, service: .avTransport), key(host: host, service: .renderingControl)]
        })

        for existingKey in subscriptions.keys where !desired.contains(existingKey) {
            await unsubscribe(key: existingKey)
        }
        for host in coordinatorHosts {
            for service: SonosService in [.avTransport, .renderingControl] {
                let k = key(host: host, service: service)
                if subscriptions[k] == nil {
                    await subscribe(host: host, service: service)
                }
            }
        }
    }

    func stopAll() async {
        for k in subscriptions.keys {
            await unsubscribe(key: k)
        }
    }

    private func key(host: String, service: SonosService) -> String { "\(host)|\(service.rawValue)" }

    private func eventPath(for service: SonosService) -> String {
        switch service {
        case .avTransport: return "/MediaRenderer/AVTransport/Event"
        case .renderingControl: return "/MediaRenderer/RenderingControl/Event"
        case .groupRenderingControl: return "/MediaRenderer/GroupRenderingControl/Event"
        case .zoneGroupTopology: return "/ZoneGroupTopology/Event"
        case .contentDirectory: return "/MediaServer/ContentDirectory/Event"
        case .alarmClock: return "/AlarmClock/Event"
        }
    }

    private func subscribe(host: String, service: SonosService) async {
        guard let callback = GENAEventServer.shared.callbackURL(path: "/notify/\(host)/\(service.rawValue)"),
              let url = URL(string: "http://\(host):1400\(eventPath(for: service))") else { return }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "SUBSCRIBE"
        request.setValue("<\(callback)>", forHTTPHeaderField: "CALLBACK")
        request.setValue("upnp:event", forHTTPHeaderField: "NT")
        request.setValue("Second-300", forHTTPHeaderField: "TIMEOUT")

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let sid = http.value(forHTTPHeaderField: "SID") else { return }

        let k = key(host: host, service: service)
        let granted = Self.parseTimeoutSeconds(from: http)
        subscriptions[k] = Subscription(sid: sid, host: host, service: service, renewTask: scheduleRenew(key: k, afterSeconds: granted))
    }

    /// Renews at a fraction of whatever the device *actually* granted, not
    /// just what we asked for. We always request 300s, but a UPnP device is
    /// free to grant less — more likely on older/embedded firmware (common
    /// on Sonos S1-era hardware) with tighter limits on how many/how long it
    /// tracks subscriptions. Assuming 300s regardless would let the
    /// subscription silently lapse on such a device, quietly falling back
    /// to the slow poll with no visible symptom beyond "updates feel slow."
    private func scheduleRenew(key k: String, afterSeconds granted: Int) -> Task<Void, Never> {
        let renewAfter = max(30, Int(Double(granted) * 0.8))
        return Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(renewAfter) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.renew(key: k)
        }
    }

    /// Parses a GENA `TIMEOUT` response header, e.g. "Second-300". Falls
    /// back to 300 for "Second-infinite" or anything unparseable, so we
    /// always keep renewing rather than risk never renewing at all.
    nonisolated static func parseTimeoutSeconds(from response: HTTPURLResponse) -> Int {
        guard let raw = response.value(forHTTPHeaderField: "TIMEOUT"),
              let digits = raw.split(separator: "-").last,
              let seconds = Int(digits) else { return 300 }
        return seconds
    }

    private func renew(key k: String) async {
        guard let sub = subscriptions[k],
              let url = URL(string: "http://\(sub.host):1400\(eventPath(for: sub.service))") else { return }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "SUBSCRIBE"
        request.setValue(sub.sid, forHTTPHeaderField: "SID")
        request.setValue("Second-300", forHTTPHeaderField: "TIMEOUT")

        if let (_, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            let granted = Self.parseTimeoutSeconds(from: http)
            subscriptions[k]?.renewTask = scheduleRenew(key: k, afterSeconds: granted)
        } else {
            // Renewal failed (e.g. the speaker rebooted and forgot us) — start fresh.
            subscriptions.removeValue(forKey: k)
            await subscribe(host: sub.host, service: sub.service)
        }
    }

    private func unsubscribe(key k: String) async {
        guard let sub = subscriptions.removeValue(forKey: k) else { return }
        sub.renewTask?.cancel()
        guard let url = URL(string: "http://\(sub.host):1400\(eventPath(for: sub.service))") else { return }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "UNSUBSCRIBE"
        request.setValue(sub.sid, forHTTPHeaderField: "SID")
        _ = try? await URLSession.shared.data(for: request)
    }

    func handleNotify(path: String, body: String) {
        // Path shape: /notify/<host>/<serviceRawValue> — we chose it ourselves in `subscribe`.
        let comps = path.split(separator: "/")
        guard comps.count >= 3, comps[0] == "notify" else { return }
        let host = String(comps[1])
        let serviceRaw = String(comps[2])

        guard let lastChangeEscaped = XMLHelpers.value(ofTag: "LastChange", in: body) else { return }
        let lastChange = XMLHelpers.unescapeXML(lastChangeEscaped)

        if serviceRaw == SonosService.avTransport.rawValue {
            if let raw = Self.attributeValue(tag: "TransportState", attribute: "val", in: lastChange),
               let state = TransportState(rawValue: raw) {
                onTransportChange?(host, state)
            }
        } else if serviceRaw == SonosService.renderingControl.rawValue {
            if let raw = Self.attributeValue(tag: "Volume", attribute: "val", in: lastChange, requiring: ("channel", "Master")),
               let volume = Int(raw) {
                onVolumeChange?(host, volume)
            }
        }
    }

    /// Finds the first `<tag ... attribute="value" .../>`, optionally
    /// requiring another attribute to match first (RenderingControl reports
    /// Volume once per channel, so we need `channel="Master"` specifically).
    static func attributeValue(tag: String, attribute: String, in xml: String, requiring: (String, String)? = nil) -> String? {
        let pattern = "<\(tag)\\b([^>]*)/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
        for match in matches {
            guard let range = Range(match.range(at: 1), in: xml) else { continue }
            let attrs = XMLHelpers.allAttributes(in: String(xml[range]))
            if let requiring, attrs[requiring.0] != requiring.1 { continue }
            if let value = attrs[attribute] { return value }
        }
        return nil
    }
}
