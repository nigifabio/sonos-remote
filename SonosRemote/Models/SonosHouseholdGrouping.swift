import Foundation

/// Pure helpers for splitting rooms by Sonos generation and for deciding
/// which groups a device can legally be paired into. Kept separate from
/// `SonosViewModel` (and out of any View) so this logic — the thing that
/// actually decides whether the sidebar shows an S1/S2 split, and which
/// pairing targets are offered — can be unit tested directly instead of
/// only observed through the UI.
enum SonosHouseholdGrouping {
    /// Splits `devices` into (s1, other) by generation — the same split
    /// `SidebarView` uses to decide whether to show a two-section layout.
    /// `.unknown` devices land in `other`, alongside S2.
    static func split(
        _ devices: [SonosDevice], generations: [String: SonosSystemGeneration]
    ) -> (s1: [SonosDevice], other: [SonosDevice]) {
        let s1 = devices.filter { generations[$0.uuid] == .s1 }
        let other = devices.filter { generations[$0.uuid] != .s1 }
        return (s1, other)
    }

    /// Groups `device` could legally be paired into: not already containing
    /// it, and the same generation as it — Sonos has no concept of a
    /// cross-household group, so offering one would just fail silently.
    static func pairableGroups(
        for device: SonosDevice, in groups: [SonosGroup], generations: [String: SonosSystemGeneration]
    ) -> [SonosGroup] {
        let deviceGeneration = generations[device.uuid] ?? .unknown
        return groups.filter { group in
            !group.members.contains(device) && (generations[group.coordinatorUUID] ?? .unknown) == deviceGeneration
        }
    }
}
