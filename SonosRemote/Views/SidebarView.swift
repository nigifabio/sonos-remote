import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var vm: SonosViewModel

    var body: some View {
        List(selection: $vm.selectedGroupID) {
            Section("Rooms") {
                ForEach(vm.allDevicesSorted) { device in
                    RoomRow(device: device)
                        .tag(vm.group(containing: device)?.id ?? device.uuid)
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
        let otherGroups = vm.groups.filter { !$0.members.contains(device) }
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
