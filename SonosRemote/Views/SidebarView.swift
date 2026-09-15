import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var vm: SonosViewModel

    /// S1 and S2 devices can never share a Sonos household, but a user can
    /// run both side by side on the same network during a phased upgrade —
    /// that shows up to us as two separate households on the same LAN. Split
    /// the room list into sections the moment that's actually detected,
    /// rather than always showing "S2 System" labeling for the common case
    /// of a single, ordinary household.
    private var s1Devices: [SonosDevice] {
        vm.allDevicesSorted.filter { vm.generation(for: $0) == .s1 }
    }
    private var otherDevices: [SonosDevice] {
        vm.allDevicesSorted.filter { vm.generation(for: $0) != .s1 }
    }

    var body: some View {
        List(selection: $vm.selectedGroupID) {
            Section(s1Devices.isEmpty ? "Rooms" : "S2 System") {
                ForEach(otherDevices) { device in
                    RoomRow(device: device)
                        .tag(vm.group(containing: device)?.id ?? device.uuid)
                }
            }
            if !s1Devices.isEmpty {
                Section("S1 System (Legacy)") {
                    ForEach(s1Devices) { device in
                        RoomRow(device: device)
                            .tag(vm.group(containing: device)?.id ?? device.uuid)
                    }
                }
            }
        }
        .navigationTitle("Sonos Remote")
        .listStyle(.sidebar)
        .overlay {
            if vm.isDiscovering && vm.groups.isEmpty {
                ProgressView()
            }
        }
    }
}

private struct RoomRow: View {
    @EnvironmentObject var vm: SonosViewModel
    let device: SonosDevice

    private var group: SonosGroup? { vm.group(containing: device) }
    private var isGrouped: Bool { (group?.members.count ?? 1) > 1 }
    private var track: TrackInfo? { vm.trackInfo(for: device) }

    var body: some View {
        HStack {
            Image(systemName: isGrouped ? "hifispeaker.2.fill" : "hifispeaker.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(device.name)
                    if isGrouped {
                        Text("grouped")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(songSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .contextMenu { pairUnpairMenu }
    }

    private var songSubtitle: String {
        guard let track, !track.title.isEmpty else { return "Nothing playing" }
        return track.artist.isEmpty ? track.title : "\(track.title) — \(track.artist)"
    }

    @ViewBuilder
    private var pairUnpairMenu: some View {
        if isGrouped {
            Button("Unpair \(device.name)", role: .destructive) {
                vm.unpair(device)
            }
        }
        // A group in a different Sonos household (a different S1/S2 system)
        // can never accept this device — Sonos itself has no such thing as
        // a cross-household group, so offering it here would just fail
        // silently when attempted.
        let otherGroups = vm.groups.filter {
            !$0.members.contains(device) && vm.generation(for: $0) == vm.generation(for: device)
        }
        if !otherGroups.isEmpty {
            Menu("Pair with…") {
                ForEach(otherGroups) { targetGroup in
                    Button(targetGroup.name) {
                        vm.pair(device, withGroup: targetGroup)
                    }
                }
            }
        }
    }
}
