import AppIntents

/// Room entity for Shortcuts/Siri. Unlike the widget's `RoomEntity` (which
/// reads a shared snapshot because it's sandboxed), this one runs inside the
/// main app and can do live SSDP discovery directly.
struct SonosRoomEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sonos Room"
    static var defaultQuery = SonosRoomEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SonosRoomEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async -> [SonosRoomEntity] {
        let devices = await SonosController.discoverGroups().flatMap(\.members)
        return devices.filter { identifiers.contains($0.uuid) }.map { SonosRoomEntity(id: $0.uuid, name: $0.name) }
    }

    func suggestedEntities() async -> [SonosRoomEntity] {
        await SonosController.discoverGroups().flatMap(\.members).map { SonosRoomEntity(id: $0.uuid, name: $0.name) }
    }
}
