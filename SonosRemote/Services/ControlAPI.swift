#if os(macOS)
import Foundation

/// The `/api/...` requests other programs on this Mac can send to the
/// running app (see `LocalHTTPServer` for who is allowed to). Kept small on
/// purpose: only what the app can do and a stateless tool can't.
@MainActor
enum ControlAPI {
    struct AnnounceBody: Decodable {
        let text: String
        var rooms: [String]?
        var volume: Int?
        var voice: String?
    }

    static let maxAnnouncementLength = 500

    static func install(for viewModel: SonosViewModel) {
        LocalHTTPServer.shared.startControlAPI { [weak viewModel] request in
            guard let viewModel else {
                return .json(503, ["ok": false, "error": "Sonos Remote is shutting down"])
            }
            return await handle(request, viewModel: viewModel)
        }
    }

    /// Matches requested room names (case-insensitively) against the rooms
    /// that exist. No names means every room.
    nonisolated static func rooms(named names: [String]?, among devices: [SonosDevice]) -> (found: [SonosDevice], unknown: [String]) {
        guard let names, !names.isEmpty else { return (devices, []) }
        var found: [SonosDevice] = []
        var unknown: [String] = []
        for name in names {
            let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
            if let device = devices.first(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == wanted }) {
                if !found.contains(device) { found.append(device) }
            } else {
                unknown.append(name)
            }
        }
        return (found, unknown)
    }

    static func handle(_ request: LocalHTTPServer.ControlRequest, viewModel: SonosViewModel) async -> LocalHTTPServer.ControlResponse {
        let roomNames = viewModel.allDevicesSorted.map(\.name)
        switch (request.method, request.path) {
        case ("GET", "/api/status"):
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            return .json(200, ["ok": true, "app": "Sonos Remote", "version": version, "rooms": roomNames])

        case ("POST", "/api/announce"):
            guard let body = try? JSONDecoder().decode(AnnounceBody.self, from: request.body) else {
                return .json(400, ["ok": false, "error": "Expected JSON like {\"text\": \"…\", \"rooms\": [\"Kitchen\"]}"])
            }
            let text = body.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= maxAnnouncementLength else {
                return .json(400, ["ok": false, "error": "The text must be 1 to \(maxAnnouncementLength) characters"])
            }
            if let volume = body.volume, !(1...100).contains(volume) {
                return .json(400, ["ok": false, "error": "volume must be between 1 and 100"])
            }
            guard !roomNames.isEmpty else {
                return .json(503, ["ok": false, "error": "No Sonos rooms have been found yet"])
            }
            let (found, unknown) = rooms(named: body.rooms, among: viewModel.allDevicesSorted)
            guard unknown.isEmpty else {
                return .json(404, ["ok": false, "error": "Unknown room: \(unknown.joined(separator: ", "))", "rooms": roomNames])
            }
            do {
                let heardIn = try await viewModel.announce(text, in: found, volume: body.volume, voice: body.voice)
                return .json(200, ["ok": true, "rooms": heardIn])
            } catch {
                return .json(502, ["ok": false, "error": SonosViewModel.describe(error)])
            }

        default:
            return .json(404, ["ok": false, "error": "No such endpoint"])
        }
    }
}
#endif
