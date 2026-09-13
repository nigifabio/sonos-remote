import Foundation
import AVFoundation
import AudioToolbox

/// Plain accumulator for captured PCM bytes. Touched only from the audio
/// tap's realtime thread while recording, and read only after the tap is
/// removed and the engine stopped — never concurrently, so no lock needed.
private final class PCMAccumulator {
    var data = Data()
}

/// Push-to-talk intercom: record a short clip from a chosen mic, then play
/// it out on the chosen room(s) like a walkie-talkie message, restoring
/// whatever was playing there before.
@MainActor
final class IntercomService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isBroadcasting = false
    @Published var lastError: String?
    @Published var availableMics: [AudioInputDevice] = []
    @Published var selectedMicID: AudioDeviceID?

    private var engine: AVAudioEngine?
    private var accumulator: PCMAccumulator?
    private var recordingStart: Date?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: 1, interleaved: true)!

    func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func refreshMics() {
        availableMics = AudioDeviceManager.inputDevices()
        if let selectedMicID, !availableMics.contains(where: { $0.id == selectedMicID }) {
            self.selectedMicID = nil // previously-selected device disappeared; fall back to system default
        }
    }

    func startRecording() {
        let engine = AVAudioEngine()
        do {
            if let selectedMicID {
                try Self.setInputDevice(selectedMicID, on: engine)
            }
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw SOAPError(message: "This microphone's format isn't supported")
            }
            let accumulator = PCMAccumulator()
            let targetFormat = self.targetFormat // avoid capturing `self` (MainActor) in the audio-thread tap below

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
                var consumed = false
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (targetFormat.sampleRate / inputFormat.sampleRate)) + 32
                guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
                var convError: NSError?
                converter.convert(to: outBuffer, error: &convError) { _, outStatus in
                    if consumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }
                guard convError == nil, outBuffer.frameLength > 0, let channelData = outBuffer.int16ChannelData else { return }
                let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
                accumulator.data.append(Data(bytes: channelData[0], count: byteCount))
            }

            try engine.start()
            self.engine = engine
            self.accumulator = accumulator
            recordingStart = Date()
            isRecording = true
            lastError = nil
        } catch {
            lastError = "Couldn't start recording: \(error.localizedDescription)"
        }
    }

    /// Stops recording and broadcasts the clip to every device in `targets`.
    func stopAndBroadcast(to targets: [SonosDevice]) {
        guard isRecording, let engine, let accumulator else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.accumulator = nil
        isRecording = false
        let duration = recordingStart.map { Date().timeIntervalSince($0) } ?? 3
        recordingStart = nil

        guard !targets.isEmpty else { return }
        let wavData = Self.makeWAVFile(pcm16: accumulator.data, sampleRate: targetFormat.sampleRate, channels: 1)
        Task {
            await broadcast(data: wavData, duration: duration, targets: targets)
        }
    }

    func cancelRecording() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        accumulator = nil
        isRecording = false
        recordingStart = nil
    }

    private static func setInputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw SOAPError(message: "No input audio unit available")
        }
        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw SOAPError(message: "Failed to select microphone (status \(status))")
        }
    }

    /// Builds a standard 44-byte-header PCM WAV file directly from raw
    /// samples. Deliberately avoids AVAudioFile for writing: its `write(from:)`
    /// requires the buffer to match the file's *processing* format, which for
    /// PCM is always float32 regardless of the on-disk settings you pass in —
    /// writing our already-converted Int16 buffer into one tripped a hard
    /// Core Audio assertion (EXC_BREAKPOINT) instead of failing gracefully.
    nonisolated static func makeWAVFile(pcm16: Data, sampleRate: Double, channels: UInt16) -> Data {
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * (bitsPerSample / 8)
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(pcm16.count)

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.appendLE(UInt32(36 + dataSize))
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.appendLE(UInt32(16))
        header.appendLE(UInt16(1)) // PCM
        header.appendLE(channels)
        header.appendLE(UInt32(sampleRate))
        header.appendLE(byteRate)
        header.appendLE(blockAlign)
        header.appendLE(bitsPerSample)
        header.append(contentsOf: "data".utf8)
        header.appendLE(dataSize)

        return header + pcm16
    }

    private func broadcast(data: Data, duration: TimeInterval, targets: [SonosDevice]) async {
        isBroadcasting = true
        defer { isBroadcasting = false }

        guard !data.isEmpty else {
            lastError = "No audio was captured"
            return
        }
        let announcementURL: URL
        do {
            announcementURL = try LocalHTTPServer.shared.serve(data: data)
        } catch {
            lastError = error.localizedDescription
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for device in targets {
                group.addTask {
                    await Self.playOnRoom(device, uri: announcementURL.absoluteString, timeout: duration + 5)
                }
            }
        }
    }

    private static func playOnRoom(_ device: SonosDevice, uri: String, timeout: TimeInterval) async {
        let snapshot = try? await SonosController.snapshot(device)
        try? await SonosController.playAnnouncement(on: device, uri: uri)
        await SonosController.waitUntilStopped(device, timeout: timeout)
        if let snapshot {
            await SonosController.restore(device, from: snapshot)
        }
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
    mutating func appendLE(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
