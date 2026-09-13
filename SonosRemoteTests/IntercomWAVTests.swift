import XCTest
@testable import SonosRemote

/// Covers the WAV header builder introduced to fix a real crash: writing an
/// Int16 buffer via AVAudioFile tripped a Core Audio assertion because
/// AVAudioFile's processing format is always float32 regardless of the
/// on-disk settings requested. See IntercomService.makeWAVFile.
final class IntercomWAVTests: XCTestCase {
    func testWAVHeaderFieldsAreCorrect() {
        let sampleCount = 1000
        let pcm = Data(repeating: 0, count: sampleCount * 2) // 16-bit mono silence
        let wav = IntercomService.makeWAVFile(pcm16: pcm, sampleRate: 44_100, channels: 1)

        XCTAssertEqual(wav.count, 44 + pcm.count)
        XCTAssertEqual(String(data: wav[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: wav[12..<16], encoding: .ascii), "fmt ")
        XCTAssertEqual(String(data: wav[36..<40], encoding: .ascii), "data")

        let audioFormat = wav[20..<22].withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(audioFormat, 1) // PCM

        let channels = wav[22..<24].withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(channels, 1)

        let sampleRate = wav[24..<28].withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(sampleRate, 44_100)

        let bitsPerSample = wav[34..<36].withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(bitsPerSample, 16)

        let dataSize = wav[40..<44].withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(dataSize, UInt32(pcm.count))
    }

    func testWAVIsValidWithEmptyAudio() {
        let wav = IntercomService.makeWAVFile(pcm16: Data(), sampleRate: 44_100, channels: 1)
        XCTAssertEqual(wav.count, 44)
    }
}
