import AppIntents

/// Live (re-discovers on every call — Shortcuts/Siri isn't latency-sensitive
/// the way a widget tap is) lookup helpers shared by the intents below.
private enum ShortcutLookup {
    static func device(uuid: String) async -> SonosDevice? {
        await SonosController.discoverGroups().flatMap(\.members).first { $0.uuid == uuid }
    }

    static func coordinator(forRoomUUID uuid: String) async -> SonosDevice? {
        let groups = await SonosController.discoverGroups()
        return groups.first { $0.members.contains { $0.uuid == uuid } }?.coordinator
    }
}

struct PlayRoomIntent: AppIntent {
    static var title: LocalizedStringResource = "Play in Room"
    @Parameter(title: "Room") var room: SonosRoomEntity

    init() {}
    init(room: SonosRoomEntity) { self.room = room }

    func perform() async throws -> some IntentResult {
        if let device = await ShortcutLookup.coordinator(forRoomUUID: room.id) {
            try? await SonosController.play(device)
        }
        return .result()
    }
}

struct PauseRoomIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Room"
    @Parameter(title: "Room") var room: SonosRoomEntity

    init() {}
    init(room: SonosRoomEntity) { self.room = room }

    func perform() async throws -> some IntentResult {
        if let device = await ShortcutLookup.coordinator(forRoomUUID: room.id) {
            try? await SonosController.pause(device)
        }
        return .result()
    }
}

struct PlayPauseRoomIntent: AppIntent {
    static var title: LocalizedStringResource = "Play/Pause Room"
    @Parameter(title: "Room") var room: SonosRoomEntity

    init() {}
    init(room: SonosRoomEntity) { self.room = room }

    func perform() async throws -> some IntentResult {
        guard let device = await ShortcutLookup.coordinator(forRoomUUID: room.id) else { return .result() }
        let state = try? await SonosController.transportState(device)
        if state == .playing {
            try? await SonosController.pause(device)
        } else {
            try? await SonosController.play(device)
        }
        return .result()
    }
}

struct NextTrackShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip to Next Track"
    @Parameter(title: "Room") var room: SonosRoomEntity

    init() {}
    init(room: SonosRoomEntity) { self.room = room }

    func perform() async throws -> some IntentResult {
        if let device = await ShortcutLookup.coordinator(forRoomUUID: room.id) {
            try? await SonosController.next(device)
        }
        return .result()
    }
}

struct SetRoomVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Room Volume"
    @Parameter(title: "Room") var room: SonosRoomEntity
    @Parameter(title: "Volume", default: 30) var volume: Int

    init() {}
    init(room: SonosRoomEntity, volume: Int) {
        self.room = room
        self.volume = volume
    }

    func perform() async throws -> some IntentResult {
        if let device = await ShortcutLookup.device(uuid: room.id) {
            try? await SonosController.setVolume(device, to: volume)
        }
        return .result()
    }
}

struct TogglePartyModeShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Sonos Party Mode"

    func perform() async throws -> some IntentResult {
        let groups = await SonosController.discoverGroups()
        guard !groups.isEmpty else { return .result() }
        let allDevices = groups.flatMap(\.members)
        let isPartyMode = groups.count == 1 && (groups.first?.members.count ?? 0) > 1
        if isPartyMode {
            await SonosController.ungroupAll(groups)
        } else if let coordinator = groups.first?.coordinator {
            await SonosController.partyMode(allDevices: allDevices, coordinator: coordinator)
        }
        return .result()
    }
}
