import Foundation

/// Talks directly to Sonos speakers over local UPnP/SOAP (port 1400).
/// No cloud, no third-party server — everything here stays on the LAN.
enum SonosController {

    // MARK: - Discovery & topology

    /// Finds Sonos hosts via SSDP, then asks the first one for the full
    /// household topology (every room, its IP, and how rooms are grouped).
    static func discoverGroups() async -> [SonosGroup] {
        let hosts = await SSDPDiscovery.discoverHosts()
        for host in hosts {
            if let groups = try? await fetchTopology(bootstrapHost: host), !groups.isEmpty {
                return groups
            }
        }
        return []
    }

    static func fetchTopology(bootstrapHost: String) async throws -> [SonosGroup] {
        let xml = try await SOAPClient.call(
            host: bootstrapHost,
            service: .zoneGroupTopology,
            action: "GetZoneGroupState",
            arguments: []
        )
        guard let stateXML = XMLHelpers.value(ofTag: "ZoneGroupState", in: xml) else { return [] }
        let unescaped = XMLHelpers.unescapeXML(stateXML)
        return parseZoneGroups(from: unescaped)
    }

    static func parseZoneGroups(from xml: String) -> [SonosGroup] {
        // Split into <ZoneGroup ...> ... </ZoneGroup> blocks manually so each
        // group's members don't leak into the next group's regex match.
        var groups: [SonosGroup] = []
        let blockPattern = "<ZoneGroup\\b[^>]*Coordinator=\"([^\"]*)\"[^>]*ID=\"([^\"]*)\"[^>]*>([\\s\\S]*?)</ZoneGroup>"
        guard let regex = try? NSRegularExpression(pattern: blockPattern) else { return [] }
        let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))

        for match in matches {
            guard let coordRange = Range(match.range(at: 1), in: xml),
                  let idRange = Range(match.range(at: 2), in: xml),
                  let bodyRange = Range(match.range(at: 3), in: xml) else { continue }

            let coordinatorUUID = String(xml[coordRange])
            let groupID = String(xml[idRange])
            let body = String(xml[bodyRange])

            let memberAttrs = XMLHelpers.attributeValues(tag: "ZoneGroupMember", attribute: "UUID", in: body)
            let members: [SonosDevice] = memberAttrs.compactMap { attrs in
                guard let uuid = attrs["UUID"],
                      let name = attrs["ZoneName"],
                      let location = attrs["Location"],
                      let host = URL(string: location)?.host else { return nil }
                // Skip satellite/bonded speakers that aren't independently addressable
                // rooms, and non-audio infrastructure like a Sonos Bridge (common in
                // older SonosNet setups, including most S1-era systems) — it appears
                // in topology but has no transport/rendering services to control.
                if attrs["Invisible"] == "1" { return nil }
                if attrs["IsZoneBridge"] == "1" { return nil }
                return SonosDevice(uuid: uuid, name: name, host: host)
            }
            guard !members.isEmpty else { continue }
            groups.append(SonosGroup(id: groupID, coordinatorUUID: coordinatorUUID, members: members))
        }
        return groups
    }

    // MARK: - Transport

    static func play(_ device: SonosDevice) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "Play",
                                       arguments: [("InstanceID", "0"), ("Speed", "1")])
    }

    static func pause(_ device: SonosDevice) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "Pause")
    }

    static func stop(_ device: SonosDevice) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "Stop")
    }

    static func next(_ device: SonosDevice) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "Next")
    }

    static func previous(_ device: SonosDevice) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "Previous")
    }

    static func transportState(_ device: SonosDevice) async throws -> TransportState {
        let xml = try await SOAPClient.call(host: device.host, service: .avTransport, action: "GetTransportInfo")
        let raw = XMLHelpers.value(ofTag: "CurrentTransportState", in: xml) ?? ""
        return TransportState(rawValue: raw) ?? .unknown
    }

    static func trackInfo(_ device: SonosDevice) async throws -> TrackInfo {
        async let positionXML = SOAPClient.call(host: device.host, service: .avTransport, action: "GetPositionInfo")
        async let stateXML = SOAPClient.call(host: device.host, service: .avTransport, action: "GetTransportInfo")

        let posXML = try await positionXML
        let transportRaw = try? await stateXML

        var info = TrackInfo()
        info.durationSeconds = XMLHelpers.seconds(fromSonosTime: XMLHelpers.value(ofTag: "TrackDuration", in: posXML) ?? "0:00:00")
        info.positionSeconds = XMLHelpers.seconds(fromSonosTime: XMLHelpers.value(ofTag: "RelTime", in: posXML) ?? "0:00:00")
        info.sourceURI = XMLHelpers.unescapeXML(XMLHelpers.value(ofTag: "TrackURI", in: posXML) ?? "")

        if let metaEscaped = XMLHelpers.value(ofTag: "TrackMetaData", in: posXML), !metaEscaped.isEmpty {
            let meta = XMLHelpers.unescapeXML(metaEscaped)
            info.title = XMLHelpers.unescapeXML(XMLHelpers.value(ofTag: "dc:title", in: meta) ?? "")
            info.artist = XMLHelpers.unescapeXML(XMLHelpers.value(ofTag: "dc:creator", in: meta) ?? "")
            info.album = XMLHelpers.unescapeXML(XMLHelpers.value(ofTag: "upnp:album", in: meta) ?? "")
            if let art = XMLHelpers.value(ofTag: "upnp:albumArtURI", in: meta) {
                info.albumArtURL = absoluteURL(art, relativeToHost: device.host)
            }
        }
        if let transportRaw, let state = XMLHelpers.value(ofTag: "CurrentTransportState", in: transportRaw) {
            info.isStream = state == TransportState.playing.rawValue && info.durationSeconds == 0
        }
        return info
    }

    private static func absoluteURL(_ path: String, relativeToHost host: String) -> URL? {
        let unescaped = XMLHelpers.unescapeXML(path)
        if unescaped.hasPrefix("http") { return URL(string: unescaped) }
        return URL(string: "http://\(host):1400\(unescaped)")
    }

    // MARK: - Volume

    static func volume(_ device: SonosDevice) async throws -> Int {
        let xml = try await SOAPClient.call(host: device.host, service: .renderingControl, action: "GetVolume",
                                             arguments: [("InstanceID", "0"), ("Channel", "Master")])
        return Int(XMLHelpers.value(ofTag: "CurrentVolume", in: xml) ?? "0") ?? 0
    }

    static func setVolume(_ device: SonosDevice, to value: Int) async throws {
        let clamped = max(0, min(100, value))
        _ = try await SOAPClient.call(host: device.host, service: .renderingControl, action: "SetVolume",
                                       arguments: [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", "\(clamped)")])
    }

    static func groupVolume(_ group: SonosGroup) async throws -> Int {
        guard let coordinator = group.coordinator else { return 0 }
        let xml = try await SOAPClient.call(host: coordinator.host, service: .groupRenderingControl, action: "GetGroupVolume")
        return Int(XMLHelpers.value(ofTag: "CurrentVolume", in: xml) ?? "0") ?? 0
    }

    static func setGroupVolume(_ group: SonosGroup, to value: Int) async throws {
        guard let coordinator = group.coordinator else { return }
        let clamped = max(0, min(100, value))
        _ = try await SOAPClient.call(host: coordinator.host, service: .groupRenderingControl, action: "SetGroupVolume",
                                       arguments: [("InstanceID", "0"), ("DesiredVolume", "\(clamped)")])
    }

    static func isMuted(_ device: SonosDevice) async throws -> Bool {
        let xml = try await SOAPClient.call(host: device.host, service: .renderingControl, action: "GetMute",
                                             arguments: [("InstanceID", "0"), ("Channel", "Master")])
        return XMLHelpers.value(ofTag: "CurrentMute", in: xml) == "1"
    }

    static func setMute(_ device: SonosDevice, muted: Bool) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .renderingControl, action: "SetMute",
                                       arguments: [("InstanceID", "0"), ("Channel", "Master"), ("DesiredMute", muted ? "1" : "0")])
    }

    static func isGroupMuted(_ group: SonosGroup) async throws -> Bool {
        guard let coordinator = group.coordinator else { return false }
        let xml = try await SOAPClient.call(host: coordinator.host, service: .groupRenderingControl, action: "GetGroupMute")
        return XMLHelpers.value(ofTag: "CurrentMute", in: xml) == "1"
    }

    static func setGroupMute(_ group: SonosGroup, muted: Bool) async throws {
        guard let coordinator = group.coordinator else { return }
        _ = try await SOAPClient.call(host: coordinator.host, service: .groupRenderingControl, action: "SetGroupMute",
                                       arguments: [("InstanceID", "0"), ("DesiredMute", muted ? "1" : "0")])
    }

    // MARK: - Grouping / party mode

    /// Joins `device` into the group led by `coordinator`.
    static func join(_ device: SonosDevice, toCoordinator coordinator: SonosDevice) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "SetAVTransportURI",
                                       arguments: [("InstanceID", "0"),
                                                   ("CurrentURI", "x-rincon:\(coordinator.uuid)"),
                                                   ("CurrentURIMetaData", "")])
    }

    /// Removes `device` from whatever group it's in, making it standalone again.
    static func unjoin(_ device: SonosDevice) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "BecomeCoordinatorOfStandaloneGroup")
    }

    /// Groups every device in `allDevices` under `coordinator` — "Party Mode".
    static func partyMode(allDevices: [SonosDevice], coordinator: SonosDevice) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for device in allDevices where device.uuid != coordinator.uuid {
                taskGroup.addTask { try? await join(device, toCoordinator: coordinator) }
            }
        }
    }

    /// Splits every group back into standalone rooms.
    static func ungroupAll(_ groups: [SonosGroup]) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for group in groups {
                for member in group.members where member.uuid != group.coordinatorUUID {
                    taskGroup.addTask { try? await unjoin(member) }
                }
            }
        }
    }

    // MARK: - Intercom (snapshot / play / restore)

    static func snapshot(_ device: SonosDevice) async throws -> TransportSnapshot {
        async let mediaXML = SOAPClient.call(host: device.host, service: .avTransport, action: "GetMediaInfo")
        async let posXML = SOAPClient.call(host: device.host, service: .avTransport, action: "GetPositionInfo")
        let media = try await mediaXML
        let pos = try await posXML
        let state = try await transportState(device)
        // The values below arrive already XML-escaped as text content inside the
        // SOAP response; unescape once here so they can pass through the normal
        // (escape-once-at-send-time) argument pipeline unchanged when restored.
        return TransportSnapshot(
            currentURI: XMLHelpers.unescapeXML(XMLHelpers.value(ofTag: "CurrentURI", in: media) ?? ""),
            currentMetadata: XMLHelpers.unescapeXML(XMLHelpers.value(ofTag: "CurrentURIMetaData", in: media) ?? ""),
            relTime: XMLHelpers.value(ofTag: "RelTime", in: pos) ?? "0:00:00",
            wasPlaying: state == .playing
        )
    }

    /// Raw (unescaped) DIDL-Lite metadata — `SOAPClient.call` escapes argument
    /// values exactly once when it builds the envelope, so callers must always
    /// pass metadata unescaped, never pre-escaped.
    private static func didlMetadata(title: String) -> String {
        """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:dc="http://purl.org/dc/elements/1.1/"><item id="intercom" parentID="-1" restricted="1"><dc:title>\(title)</dc:title><upnp:class>object.item.audioItem.musicTrack</upnp:class></item></DIDL-Lite>
        """
    }

    static func playAnnouncement(on device: SonosDevice, uri: String) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "SetAVTransportURI",
                                       arguments: [("InstanceID", "0"), ("CurrentURI", uri),
                                                   ("CurrentURIMetaData", didlMetadata(title: "Intercom"))])
        try await play(device)
    }

    static func restore(_ device: SonosDevice, from snapshot: TransportSnapshot) async {
        guard !snapshot.currentURI.isEmpty else { return }
        _ = try? await SOAPClient.call(host: device.host, service: .avTransport, action: "SetAVTransportURI",
                                        arguments: [("InstanceID", "0"),
                                                    ("CurrentURI", snapshot.currentURI),
                                                    ("CurrentURIMetaData", snapshot.currentMetadata)])
        if !snapshot.relTime.isEmpty && snapshot.relTime != "NOT_IMPLEMENTED" {
            _ = try? await SOAPClient.call(host: device.host, service: .avTransport, action: "Seek",
                                            arguments: [("InstanceID", "0"), ("Unit", "REL_TIME"), ("Target", snapshot.relTime)])
        }
        if snapshot.wasPlaying {
            try? await play(device)
        }
    }

    /// Polls until the device stops playing (the announcement finished) or `timeout` elapses.
    static func waitUntilStopped(_ device: SonosDevice, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let state = try? await transportState(device), state == .stopped { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    // MARK: - Browse (Favorites / Playlists / Local Library / Queue)

    /// Raw `ContentDirectory.Browse` call. `objectID` is a Sonos-defined root
    /// like `FV:2` (Favorites), `SQ:` (Playlists), `A:ALBUM` (local library),
    /// or `Q:0` (the current queue) — or any container `id` returned by a
    /// previous browse, to drill in further.
    static func browse(
        _ device: SonosDevice, objectID: String,
        startingIndex: Int = 0, requestedCount: Int = 200
    ) async throws -> [BrowseItem] {
        let xml = try await SOAPClient.call(
            host: device.host, service: .contentDirectory, action: "Browse",
            arguments: [
                ("ObjectID", objectID),
                ("BrowseFlag", "BrowseDirectChildren"),
                ("Filter", "*"),
                ("StartingIndex", "\(startingIndex)"),
                ("RequestedCount", "\(requestedCount)"),
                ("SortCriteria", "")
            ]
        )
        guard let resultEscaped = XMLHelpers.value(ofTag: "Result", in: xml) else { return [] }
        let didl = XMLHelpers.unescapeXML(resultEscaped)
        return DIDLParser.parseItems(from: didl, host: device.host)
    }

    static func browseFavorites(_ device: SonosDevice) async throws -> [BrowseItem] {
        try await browse(device, objectID: BrowseRoot.favorites)
    }

    static func browsePlaylists(_ device: SonosDevice) async throws -> [BrowseItem] {
        try await browse(device, objectID: BrowseRoot.playlists)
    }

    static func getQueue(_ device: SonosDevice) async throws -> [BrowseItem] {
        try await browse(device, objectID: BrowseRoot.queue)
    }

    /// Plays a Favorite, Playlist, local-library album/track, or any other
    /// browse result. Favorites already carry a self-contained, directly
    /// playable URI+metadata; containers (playlists/albums/folders) are
    /// played by replacing the queue and pointing the transport at it — the
    /// same mechanism Sonos' own apps use.
    static func play(_ item: BrowseItem, on device: SonosDevice) async throws {
        if item.isContainer {
            _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "RemoveAllTracksFromQueue")
            _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "AddURIToQueue",
                                           arguments: [("InstanceID", "0"), ("EnqueuedURI", item.uri),
                                                       ("EnqueuedURIMetaData", item.metadata),
                                                       ("DesiredFirstTrackNumberEnqueued", "0"), ("EnqueueAsNext", "1")])
            _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "SetAVTransportURI",
                                           arguments: [("InstanceID", "0"), ("CurrentURI", "x-rincon-queue:\(device.uuid)#0"),
                                                       ("CurrentURIMetaData", "")])
        } else {
            _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "SetAVTransportURI",
                                           arguments: [("InstanceID", "0"), ("CurrentURI", item.uri),
                                                       ("CurrentURIMetaData", item.metadata)])
        }
        try await play(device)
    }

    // MARK: - Queue management

    static func playFromQueue(_ device: SonosDevice, trackNumber: Int) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "Seek",
                                       arguments: [("InstanceID", "0"), ("Unit", "TRACK_NR"), ("Target", "\(trackNumber)")])
        try await play(device)
    }

    static func removeFromQueue(_ device: SonosDevice, trackNumber: Int) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "RemoveTrackFromQueue",
                                       arguments: [("InstanceID", "0"), ("ObjectID", "Q:0/\(trackNumber)"), ("UpdateID", "0")])
    }

    static func clearQueue(_ device: SonosDevice) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "RemoveAllTracksFromQueue")
    }

    /// Moves the track at `fromNumber` (1-based, as returned by the queue
    /// browse) to just before `toNumber`.
    static func reorderQueue(_ device: SonosDevice, fromTrackNumber: Int, toTrackNumber: Int) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "ReorderTracksInQueue",
                                       arguments: [("InstanceID", "0"), ("StartingIndex", "\(fromTrackNumber)"),
                                                   ("NumberOfTracks", "1"), ("InsertBefore", "\(toTrackNumber)"),
                                                   ("UpdateID", "0")])
    }

    // MARK: - Sleep timer

    static func setSleepTimer(_ device: SonosDevice, seconds: Int?) async throws {
        let duration: String
        if let seconds, seconds > 0 {
            duration = String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        } else {
            duration = ""
        }
        _ = try await SOAPClient.call(host: device.host, service: .avTransport, action: "ConfigureSleepTimer",
                                       arguments: [("InstanceID", "0"), ("NewSleepTimerDuration", duration)])
    }

    /// Remaining seconds, or nil if no sleep timer is set.
    static func getSleepTimer(_ device: SonosDevice) async throws -> Int? {
        let xml = try await SOAPClient.call(host: device.host, service: .avTransport, action: "GetRemainingSleepTimerDuration")
        guard let remaining = XMLHelpers.value(ofTag: "RemainingSleepTimerDuration", in: xml), !remaining.isEmpty else { return nil }
        return XMLHelpers.seconds(fromSonosTime: remaining)
    }

    // MARK: - EQ (bass / treble / loudness)

    static func getBass(_ device: SonosDevice) async throws -> Int {
        let xml = try await SOAPClient.call(host: device.host, service: .renderingControl, action: "GetBass")
        return Int(XMLHelpers.value(ofTag: "CurrentBass", in: xml) ?? "0") ?? 0
    }

    static func setBass(_ device: SonosDevice, to value: Int) async throws {
        let clamped = max(-10, min(10, value))
        _ = try await SOAPClient.call(host: device.host, service: .renderingControl, action: "SetBass",
                                       arguments: [("InstanceID", "0"), ("DesiredBass", "\(clamped)")])
    }

    static func getTreble(_ device: SonosDevice) async throws -> Int {
        let xml = try await SOAPClient.call(host: device.host, service: .renderingControl, action: "GetTreble")
        return Int(XMLHelpers.value(ofTag: "CurrentTreble", in: xml) ?? "0") ?? 0
    }

    static func setTreble(_ device: SonosDevice, to value: Int) async throws {
        let clamped = max(-10, min(10, value))
        _ = try await SOAPClient.call(host: device.host, service: .renderingControl, action: "SetTreble",
                                       arguments: [("InstanceID", "0"), ("DesiredTreble", "\(clamped)")])
    }

    static func getLoudness(_ device: SonosDevice) async throws -> Bool {
        let xml = try await SOAPClient.call(host: device.host, service: .renderingControl, action: "GetLoudness",
                                             arguments: [("InstanceID", "0"), ("Channel", "Master")])
        return XMLHelpers.value(ofTag: "CurrentLoudness", in: xml) == "1"
    }

    static func setLoudness(_ device: SonosDevice, enabled: Bool) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .renderingControl, action: "SetLoudness",
                                       arguments: [("InstanceID", "0"), ("Channel", "Master"), ("DesiredLoudness", enabled ? "1" : "0")])
    }

    // MARK: - Alarms

    static func listAlarms(_ device: SonosDevice) async throws -> [SonosAlarm] {
        let xml = try await SOAPClient.call(host: device.host, service: .alarmClock, action: "ListAlarms")
        guard let listEscaped = XMLHelpers.value(ofTag: "CurrentAlarmList", in: xml) else { return [] }
        let list = XMLHelpers.unescapeXML(listEscaped)
        let alarmAttrs = XMLHelpers.attributeValues(tag: "Alarm", attribute: "ID", in: list)
        return alarmAttrs.compactMap { attrs in
            guard let id = attrs["ID"] else { return nil }
            return SonosAlarm(
                id: id,
                startTime: attrs["StartTime"] ?? "07:00:00",
                duration: attrs["Duration"] ?? "01:00:00",
                recurrence: attrs["Recurrence"] ?? "DAILY",
                enabled: attrs["Enabled"] == "1",
                roomUUID: attrs["RoomUUID"] ?? device.uuid,
                programURI: attrs["ProgramURI"] ?? "x-rincon-buzzer:0",
                programMetaData: attrs["ProgramMetaData"] ?? "",
                playMode: attrs["PlayMode"] ?? "NORMAL",
                volume: Int(attrs["Volume"] ?? "30") ?? 30,
                includeLinkedZones: attrs["IncludeLinkedZones"] == "1"
            )
        }
    }

    /// Creates a new alarm. Defaults to the built-in Sonos chime
    /// (`x-rincon-buzzer:0`) so it works without picking a music source.
    static func createAlarm(
        device: SonosDevice, startTime: String, duration: String = "00:30:00",
        recurrence: String = "DAILY", volume: Int = 30
    ) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .alarmClock, action: "CreateAlarm",
                                       arguments: [
                                           ("StartLocalTime", startTime), ("Duration", duration),
                                           ("Recurrence", recurrence), ("Enabled", "1"),
                                           ("RoomUUID", device.uuid), ("ProgramURI", "x-rincon-buzzer:0"),
                                           ("ProgramMetaData", ""), ("PlayMode", "NORMAL"),
                                           ("Volume", "\(volume)"), ("IncludeLinkedZones", "0")
                                       ])
    }

    static func updateAlarm(_ alarm: SonosAlarm, on device: SonosDevice) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .alarmClock, action: "UpdateAlarm",
                                       arguments: [
                                           ("ID", alarm.id), ("StartLocalTime", alarm.startTime),
                                           ("Duration", alarm.duration), ("Recurrence", alarm.recurrence),
                                           ("Enabled", alarm.enabled ? "1" : "0"), ("RoomUUID", alarm.roomUUID),
                                           ("ProgramURI", alarm.programURI), ("ProgramMetaData", alarm.programMetaData),
                                           ("PlayMode", alarm.playMode), ("Volume", "\(alarm.volume)"),
                                           ("IncludeLinkedZones", alarm.includeLinkedZones ? "1" : "0")
                                       ])
    }

    static func setAlarmEnabled(_ alarm: SonosAlarm, enabled: Bool, on device: SonosDevice) async throws {
        var updated = alarm
        updated.enabled = enabled
        try await updateAlarm(updated, on: device)
    }

    static func deleteAlarm(_ alarm: SonosAlarm, on device: SonosDevice) async throws {
        _ = try await SOAPClient.call(host: device.host, service: .alarmClock, action: "DestroyAlarm",
                                       arguments: [("ID", alarm.id)])
    }
}
