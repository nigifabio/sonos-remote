import AppIntents

struct RoomEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sonos Room"
    static var defaultQuery = RoomEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct RoomEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async -> [RoomEntity] {
        let rooms = WidgetSharedStore.read()?.rooms ?? []
        return rooms.filter { identifiers.contains($0.id) }.map { RoomEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async -> [RoomEntity] {
        let rooms = WidgetSharedStore.read()?.rooms ?? []
        return rooms.map { RoomEntity(id: $0.id, name: $0.name) }
    }
}
