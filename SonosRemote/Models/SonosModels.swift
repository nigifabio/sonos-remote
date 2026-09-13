import Foundation

/// A single physical Sonos speaker, as reported by ZoneGroupTopology.
struct SonosDevice: Identifiable, Hashable {
    let uuid: String       // e.g. "RINCON_XXXXXXXXXXXX01400"
    let name: String       // room name, e.g. "Kitchen"
    let host: String       // IP address
    let port: Int = 1400

    var id: String { uuid }
    var baseURL: URL { URL(string: "http://\(host):\(port)")! }
}

/// A group of one or more devices playing in sync, led by a coordinator.
struct SonosGroup: Identifiable, Hashable {
    let id: String              // group ID from topology
    let coordinatorUUID: String
    var members: [SonosDevice]  // includes the coordinator

    var coordinator: SonosDevice? { members.first { $0.uuid == coordinatorUUID } }
    var name: String {
        members.map(\.name).sorted().joined(separator: " + ")
    }
}

enum TransportState: String {
    case playing = "PLAYING"
    case paused = "PAUSED_PLAYBACK"
    case stopped = "STOPPED"
    case transitioning = "TRANSITIONING"
    case unknown = ""
}

struct TrackInfo: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var albumArtURL: URL?
    var durationSeconds: Int = 0
    var positionSeconds: Int = 0
    var isStream: Bool = false
}

struct TransportSnapshot {
    var currentURI: String
    var currentMetadata: String
    var relTime: String
    var wasPlaying: Bool
}
