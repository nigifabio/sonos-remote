import AppIntents
import WidgetKit

struct SonosWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Room"
    static var description = IntentDescription("Choose which Sonos room this widget controls.")

    @Parameter(title: "Room")
    var room: RoomEntity?
}

/// Looks up a room's coordinator device (the one that actually owns
/// transport/queue for its whole group) from the last-published snapshot.
private func coordinatorDevice(for roomID: String, in snapshot: WidgetSnapshot) -> SonosDevice? {
    guard let roomInfo = snapshot.rooms.first(where: { $0.id == roomID }),
          let coordinatorInfo = snapshot.rooms.first(where: { $0.id == roomInfo.groupCoordinatorUUID }) else {
        return nil
    }
    return SonosDevice(uuid: coordinatorInfo.id, name: coordinatorInfo.name, host: coordinatorInfo.host)
}

struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    @Parameter(title: "Room") var room: RoomEntity

    init() {}
    init(room: RoomEntity) { self.room = room }

    func perform() async throws -> some IntentResult {
        guard let snapshot = WidgetSharedStore.read(),
              let roomInfo = snapshot.rooms.first(where: { $0.id == room.id }),
              let device = coordinatorDevice(for: room.id, in: snapshot) else { return .result() }
        let isPlaying = snapshot.nowPlayingByGroup[roomInfo.groupID]?.isPlaying ?? false
        if isPlaying {
            try? await SonosController.pause(device)
        } else {
            try? await SonosController.play(device)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track"
    @Parameter(title: "Room") var room: RoomEntity

    init() {}
    init(room: RoomEntity) { self.room = room }

    func perform() async throws -> some IntentResult {
        if let snapshot = WidgetSharedStore.read(), let device = coordinatorDevice(for: room.id, in: snapshot) {
            try? await SonosController.next(device)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Track"
    @Parameter(title: "Room") var room: RoomEntity

    init() {}
    init(room: RoomEntity) { self.room = room }

    func perform() async throws -> some IntentResult {
        if let snapshot = WidgetSharedStore.read(), let device = coordinatorDevice(for: room.id, in: snapshot) {
            try? await SonosController.previous(device)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct AdjustVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Adjust Volume"
    @Parameter(title: "Room") var room: RoomEntity
    @Parameter(title: "Delta") var delta: Int

    init() {}
    init(room: RoomEntity, delta: Int) {
        self.room = room
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        guard let snapshot = WidgetSharedStore.read(),
              let roomInfo = snapshot.rooms.first(where: { $0.id == room.id }) else { return .result() }
        let device = SonosDevice(uuid: roomInfo.id, name: roomInfo.name, host: roomInfo.host)
        let newVolume = max(0, min(100, roomInfo.volume + delta))
        try? await SonosController.setVolume(device, to: newVolume)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct TogglePartyModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Party Mode"

    func perform() async throws -> some IntentResult {
        guard let snapshot = WidgetSharedStore.read(), !snapshot.rooms.isEmpty else { return .result() }
        let allDevices = snapshot.rooms.map { SonosDevice(uuid: $0.id, name: $0.name, host: $0.host) }
        if snapshot.isPartyMode {
            for room in snapshot.rooms where room.id != room.groupCoordinatorUUID {
                if let device = allDevices.first(where: { $0.uuid == room.id }) {
                    try? await SonosController.unjoin(device)
                }
            }
        } else if let coordinator = allDevices.first {
            await SonosController.partyMode(allDevices: allDevices, coordinator: coordinator)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
