import Foundation

/// Snapshot of everything the widget needs, written by the main app after
/// every poll/action and read by the (sandboxed) widget extension via an
/// App Group container — the only sanctioned way to share live data with a
/// WidgetKit extension, which cannot reach the LAN on its own for discovery.
struct WidgetRoomSnapshot: Codable, Identifiable {
    var id: String // device uuid
    var name: String
    var host: String
    var volume: Int
    var groupID: String
    var groupCoordinatorUUID: String
}

struct WidgetNowPlaying: Codable {
    var title: String
    var artist: String
    var isPlaying: Bool
}

struct WidgetSnapshot: Codable {
    var rooms: [WidgetRoomSnapshot]
    var nowPlayingByGroup: [String: WidgetNowPlaying] // groupID -> now playing
    var isPartyMode: Bool
    var updatedAt: Date
}

enum WidgetSharedStore {
    static let appGroupID = "group.com.fabionigi.SonosRemote"
    private static let fileName = "widget-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
