import XCTest
@testable import SonosRemote

final class SonosGenerationDetectorTests: XCTestCase {
    func testDetectsS2FromRealCapturedEra300Description() {
        // Captured live from a real Sonos Era 300.
        let description = SonosDeviceDescription(modelName: "Sonos Era 300", modelNumber: "S41", displayVersion: "18.8")
        XCTAssertEqual(SonosGenerationDetector.detect(from: description), .s2)
    }

    func testDetectsS1FromKnownLegacyOnlyModelNumber() {
        for modelNumber in ["ZP80", "ZP90", "ZP100", "ZP120", "CR100", "zp100"] {
            let description = SonosDeviceDescription(modelName: "Sonos ZonePlayer", modelNumber: modelNumber, displayVersion: "11.4")
            XCTAssertEqual(SonosGenerationDetector.detect(from: description), .s1, "modelNumber \(modelNumber) should be S1")
        }
    }

    func testDetectsS1FromLowDisplayVersionEvenOnAmbiguousModel() {
        // "Play:5" has both an S1-only Gen 1 and an S2-capable Gen 2 under
        // the same name — the version number, not the name, is what tells
        // them apart. S1 was frozen around version 11.x.
        let description = SonosDeviceDescription(modelName: "Sonos PLAY:5", modelNumber: "S5", displayVersion: "11.4")
        XCTAssertEqual(SonosGenerationDetector.detect(from: description), .s1)
    }

    func testDetectsS2FromHighDisplayVersionOnAmbiguousModel() {
        let description = SonosDeviceDescription(modelName: "Sonos PLAY:5", modelNumber: "S27", displayVersion: "16.0")
        XCTAssertEqual(SonosGenerationDetector.detect(from: description), .s2)
    }

    func testUnknownWhenDisplayVersionIsMissingOrUnparseable() {
        XCTAssertEqual(SonosGenerationDetector.detect(from: SonosDeviceDescription()), .unknown)
        let malformed = SonosDeviceDescription(modelName: "X", modelNumber: "X", displayVersion: "not-a-version")
        XCTAssertEqual(SonosGenerationDetector.detect(from: malformed), .unknown)
    }

    func testBoundaryAtVersionTwelve() {
        XCTAssertEqual(SonosGenerationDetector.detect(from: .init(displayVersion: "12.0")), .s2)
        XCTAssertEqual(SonosGenerationDetector.detect(from: .init(displayVersion: "11.99")), .s1)
    }
}
