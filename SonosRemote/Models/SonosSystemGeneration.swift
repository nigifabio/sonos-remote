import Foundation

/// Which Sonos software generation a device belongs to. S1 and S2 devices
/// can never share one household, but a user can run both side by side on
/// the same network during a phased upgrade — that shows up to us as two
/// separate households discovered on the same LAN (see
/// `SonosController.discoverGroups`).
enum SonosSystemGeneration: String, Codable {
    case s1 = "S1"
    case s2 = "S2"
    case unknown = "Unknown"
}

/// The identifying fields from a device's `/xml/device_description.xml` —
/// standard UPnP device description, unrelated to the S1/S2 split itself.
struct SonosDeviceDescription {
    var modelName: String = ""
    var modelNumber: String = ""
    var displayVersion: String = ""
}

enum SonosGenerationDetector {
    /// Product lines Sonos discontinued outright rather than giving an
    /// S2-capable successor under the same name — unlike Play:5,
    /// Connect, and Connect:Amp, which each have both an S1-only Gen 1
    /// and an S2-capable Gen 2 sharing the same model name, so a name/
    /// number match alone can't tell those apart. These are unambiguous.
    private static let legacyOnlyModelNumbers: Set<String> = ["ZP80", "ZP90", "ZP100", "ZP120", "CR100"]

    /// Best-effort classification — Sonos doesn't expose an explicit "this
    /// household is S1/S2" flag over local UPnP. Uses two independent
    /// signals: (1) a definitely-legacy-only model number, and (2) the
    /// `displayVersion` major number, since Sonos froze S1 firmware around
    /// version 11.x before relaunching S2 at a higher number. Verified live
    /// that a real S2 device reports a `displayVersion` like "18.8" —
    /// unverified against real S1 hardware, since none is available to test.
    static func detect(from description: SonosDeviceDescription) -> SonosSystemGeneration {
        if legacyOnlyModelNumbers.contains(description.modelNumber.uppercased()) {
            return .s1
        }
        if let majorString = description.displayVersion.split(separator: ".").first,
           let major = Int(majorString) {
            return major >= 12 ? .s2 : .s1
        }
        return .unknown
    }
}
