#if os(macOS)
import Foundation

/// Plays a short clip on chosen rooms and puts back whatever was playing —
/// shared by the push-to-talk intercom, typed (spoken) announcements, and
/// the local control endpoint other tools call.
enum AnnouncementService {
    /// Where a clip is sent, and which rooms end up hearing it.
    struct Target: Equatable {
        let player: SonosDevice
        let rooms: [SonosDevice]
    }

    /// Works out who to send the clip to. A grouped room that isn't the
    /// coordinator can play on its own (it drops out and rejoins after). A
    /// coordinator can't: whatever it plays, its whole group plays — so
    /// asking for the coordinator means the whole group, sent once, in sync,
    /// instead of also detaching each member to play its own copy.
    static func targets(for requested: [SonosDevice], in groups: [SonosGroup]) -> [Target] {
        var result: [Target] = []
        var placed = Set<String>()
        for group in groups {
            let wanted = group.members.filter { requested.contains($0) }
            guard !wanted.isEmpty else { continue }
            if let coordinator = group.coordinator, wanted.contains(coordinator) {
                result.append(Target(player: coordinator, rooms: group.members))
            } else {
                result.append(contentsOf: wanted.map { Target(player: $0, rooms: [$0]) })
            }
            placed.formUnion(wanted.map(\.uuid))
        }
        for device in requested where !placed.contains(device.uuid) {
            result.append(Target(player: device, rooms: [device]))
        }
        return result
    }

    // MARK: - Speech

    /// Speaks `text` into a WAV using the system voice (or `voice`, a name
    /// from System Settings ▸ Accessibility ▸ Spoken Content).
    static func synthesize(_ text: String, voice: String? = nil) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SonosRemoteSpeech-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // The text goes in through a file, not an argument, so a message
        // that starts with "-" can't be read as an option.
        let textFile = directory.appendingPathComponent("text.txt")
        let audioFile = directory.appendingPathComponent("speech.wav")
        try Data(text.utf8).write(to: textFile)

        var arguments = ["-o", audioFile.path, "--data-format=LEI16@44100", "-f", textFile.path]
        if let voice, !voice.isEmpty { arguments = ["-v", voice] + arguments }

        let status = try await run("/usr/bin/say", arguments)
        guard status == 0, let raw = try? Data(contentsOf: audioFile),
              let wav = canonicalWAV(from: raw) else {
            throw SOAPError(message: voice == nil
                ? "Couldn't turn that text into speech"
                : "Couldn't turn that text into speech (is \"\(voice ?? "")\" an installed voice?)")
        }
        return wav
    }

    private static func run(_ path: String, _ arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    /// Rebuilds a WAV as a bare header + samples. `say` pads its files with
    /// JUNK/FLLR chunks ahead of the audio; a plain 44-byte header is the
    /// form already known to play on every speaker.
    static func canonicalWAV(from data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 12, String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else { return nil }
        func u32(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 }
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }

        var offset = 12
        var format: (channels: Int, sampleRate: Int, bits: Int)?
        while offset + 8 <= bytes.count {
            let id = String(bytes: bytes[offset..<offset + 4], encoding: .ascii) ?? ""
            let size = u32(offset + 4)
            let body = offset + 8
            if id == "fmt ", body + 16 <= bytes.count {
                guard u16(body) == 1 else { return nil } // PCM only
                format = (u16(body + 2), u32(body + 4), u16(body + 14))
            } else if id == "data" {
                guard let format, format.bits == 16, format.channels > 0 else { return nil }
                let end = min(body + size, bytes.count)
                return IntercomService.makeWAVFile(
                    pcm16: Data(bytes[body..<end]), sampleRate: Double(format.sampleRate), channels: UInt16(format.channels)
                )
            }
            offset = body + size + (size & 1)
        }
        return nil
    }

    /// Length of a WAV produced by `makeWAVFile`/`canonicalWAV`, in seconds.
    static func duration(ofWAV data: Data) -> TimeInterval {
        guard data.count > 44 else { return 0 }
        let bytes = [UInt8](data.prefix(44))
        let byteRate = Int(bytes[28]) | Int(bytes[29]) << 8 | Int(bytes[30]) << 16 | Int(bytes[31]) << 24
        return byteRate > 0 ? Double(data.count - 44) / Double(byteRate) : 0
    }

    // MARK: - Playback

    /// Plays `wav` on every target at once. Returns the players it failed
    /// to start on.
    @discardableResult
    static func play(_ wav: Data, on targets: [Target], volume: Int? = nil, duration: TimeInterval? = nil) async throws -> [SonosDevice] {
        guard !wav.isEmpty else { throw SOAPError(message: "No audio was captured") }
        let url = try LocalHTTPServer.shared.serve(data: wav)
        let timeout = (duration ?? Self.duration(ofWAV: wav)) + 5
        return await withTaskGroup(of: SonosDevice?.self) { taskGroup in
            for target in targets {
                taskGroup.addTask {
                    await playOne(target, uri: url.absoluteString, timeout: timeout, volume: volume) ? nil : target.player
                }
            }
            var failed: [SonosDevice] = []
            for await player in taskGroup { if let player { failed.append(player) } }
            return failed
        }
    }

    private static func playOne(_ target: Target, uri: String, timeout: TimeInterval, volume: Int?) async -> Bool {
        let snapshot = try? await SonosController.snapshot(target.player)

        var previousVolumes: [(SonosDevice, Int)] = []
        if let volume {
            for room in target.rooms {
                guard let current = try? await SonosController.volume(room) else { continue }
                previousVolumes.append((room, current))
                try? await SonosController.setVolume(room, to: volume)
            }
        }
        func putVolumesBack() async {
            for (room, previous) in previousVolumes { try? await SonosController.setVolume(room, to: previous) }
        }

        do {
            try await SonosController.playAnnouncement(on: target.player, uri: uri)
        } catch {
            await putVolumesBack()
            return false
        }
        await SonosController.waitUntilStopped(target.player, timeout: timeout)
        await putVolumesBack()
        if let snapshot {
            await SonosController.restore(target.player, from: snapshot)
        }
        return true
    }
}

extension SonosViewModel {
    /// Speaks `text` in `rooms`. Returns the names of every room that hears
    /// it (more than was asked for when one of them leads a group).
    func announce(_ text: String, in rooms: [SonosDevice], volume: Int? = nil, voice: String? = nil) async throws -> [String] {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw SOAPError(message: "There is nothing to say") }
        let targets = AnnouncementService.targets(for: rooms, in: groups)
        guard !targets.isEmpty else { throw SOAPError(message: "No room was chosen") }

        let wav = try await AnnouncementService.synthesize(message, voice: voice)
        let failed = try await AnnouncementService.play(wav, on: targets, volume: volume)
        if failed.count == targets.count {
            throw SOAPError(message: "None of the rooms accepted the announcement")
        }
        return targets.filter { !failed.contains($0.player) }.flatMap(\.rooms).map(\.name)
    }
}
#endif
