import Foundation

/// Party Mode, worked out per household. Rooms can only be grouped inside
/// their own household, so "group everything" means "make every household
/// that has more than one room into a single group" — an S1 system next to
/// an S2 system is never joined to it, and a one-room household is ignored.
enum SonosPartyMode {
    /// One step of turning Party Mode on: join `joiners` to `coordinator`.
    struct Step: Equatable {
        let coordinator: SonosDevice
        let joiners: [SonosDevice]
    }

    /// Groups bucketed by household, in order of first appearance.
    static func households(_ groups: [SonosGroup]) -> [[SonosGroup]] {
        var order: [String] = []
        var buckets: [String: [SonosGroup]] = [:]
        for group in groups {
            if buckets[group.householdID] == nil { order.append(group.householdID) }
            buckets[group.householdID, default: []].append(group)
        }
        return order.compactMap { buckets[$0] }
    }

    private static func roomCount(_ household: [SonosGroup]) -> Int {
        household.reduce(0) { $0 + $1.members.count }
    }

    /// On when every household with more than one room is a single group.
    static func isOn(_ groups: [SonosGroup]) -> Bool {
        let multiRoom = households(groups).filter { roomCount($0) > 1 }
        return !multiRoom.isEmpty && multiRoom.allSatisfy { $0.count == 1 }
    }

    /// Whether the toggle can do anything: there is something to group, or
    /// something grouped to split.
    static func canToggle(_ groups: [SonosGroup]) -> Bool {
        households(groups).contains { roomCount($0) > 1 }
    }

    /// What to join to what. In each household the group that keeps playing
    /// is, in order of preference: one that is playing now, the one the user
    /// has selected, or the largest — so turning Party Mode on spreads the
    /// current music instead of replacing it with whatever was listed first.
    static func plan(_ groups: [SonosGroup], playingGroupIDs: Set<String>, preferredGroupID: String?) -> [Step] {
        households(groups).compactMap { household in
            guard household.count > 1 else { return nil }
            let target = household.first { playingGroupIDs.contains($0.id) }
                ?? household.first { $0.id == preferredGroupID }
                ?? household.max { $0.members.count < $1.members.count }
            guard let target, let coordinator = target.coordinator else { return nil }
            let joiners = household.filter { $0.id != target.id }.flatMap(\.members)
            return Step(coordinator: coordinator, joiners: joiners)
        }
    }

    /// Every non-coordinator member, i.e. who to un-join to split all groups.
    static func roomsToSplit(_ groups: [SonosGroup]) -> [SonosDevice] {
        groups.flatMap { group in group.members.filter { $0.uuid != group.coordinatorUUID } }
    }
}
