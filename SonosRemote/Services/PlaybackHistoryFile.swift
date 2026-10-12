import Foundation

/// The play history as a plain JSON file other tools can read — the Sonos
/// MCP server uses it, since Sonos itself keeps no history and a tool that
/// only runs while it is being called can't build one. The app owns the
/// file and rewrites it whole on every change; readers only read.
enum PlaybackHistoryFile {
    struct Document: Codable, Equatable {
        var version = 1
        let updated: Date
        let entries: [Entry]
    }

    struct Entry: Codable, Equatable {
        let playedAt: Date
        let room: String
        let title: String
        let artist: String
        let album: String
        let service: String
        /// The Favorite/Playlist it was started from, when known.
        let source: String?
        let uri: String?

        enum CodingKeys: String, CodingKey {
            case playedAt = "played_at"
            case room, title, artist, album, service, source, uri
        }
    }

    /// `~/Library/Application Support/SonosRemote/history.json`
    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SonosRemote", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    static func document(from history: [PlaybackHistoryEntry], updated: Date = Date()) -> Document {
        Document(updated: updated, entries: history.map {
            Entry(playedAt: $0.date, room: $0.groupName, title: $0.title, artist: $0.artist,
                  album: $0.album, service: $0.service.rawValue, source: $0.sourceLabel, uri: $0.uri)
        })
    }

    static func encode(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    static func write(_ history: [PlaybackHistoryEntry], to url: URL) {
        guard let data = try? encode(document(from: history)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
