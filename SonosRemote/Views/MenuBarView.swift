import SwiftUI
import AppKit

/// Compact popover shown when the menu bar icon is clicked: each group with
/// its own volume slider above the rooms in it, play/pause, the one-tap
/// routines, and Party Mode.
struct MenuBarView: View {
    @EnvironmentObject var vm: SonosViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var showingHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            roomList
            Divider()
            partyModeRow
            routinesRow
            if let banner = vm.banner {
                BannerView(banner: banner, compact: true, onDismiss: vm.dismissBanner)
            }
            Divider()
            recentlyPlayedSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .task {
            // Opening the tray re-reads grouping from the known speakers
            // (fast) rather than rescanning the network every time.
            if !vm.start() { await vm.refreshKnownTopology() }
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView().environmentObject(vm)
        }
    }

    private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Recently Played", systemImage: "clock.arrow.circlepath")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("See All") { showingHistory = true }
                    .buttonStyle(.borderless)
                    .font(.caption2)
            }
            if let last = vm.lastPlayed {
                recentRow(icon: "music.note", title: last.title, subtitle: last.artist)
            } else {
                Text("Nothing played yet").font(.caption2).foregroundStyle(.tertiary)
            }
            if let playlist = vm.lastSpotifyPlaylist, let name = playlist.sourceLabel {
                recentRow(icon: "music.note.list", title: name, subtitle: "Spotify Playlist")
            } else if let track = vm.lastSpotifyTrack {
                recentRow(icon: "music.note.list", title: track.title, subtitle: "Last Spotify track")
            }
        }
    }

    private func recentRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "hifispeaker.fill")
                .foregroundStyle(Color.accentColor)
            Text("Sonos Remote")
                .font(.headline)
            Spacer()
            Button {
                Task { await vm.refreshTopology() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Rescan for Sonos speakers")
        }
    }

    @ViewBuilder
    private var roomList: some View {
        if vm.allDevicesSorted.isEmpty {
            Text(vm.isDiscovering ? "Looking for speakers…" : (vm.errorMessage ?? "No speakers found"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(vm.groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { group in
                        if group.members.count > 1 {
                            MenuBarGroupSection(group: group)
                        } else if let device = group.members.first {
                            MenuBarRoomRow(device: device, showsTransport: true)
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
        }
    }

    private var partyModeRow: some View {
        Toggle(isOn: Binding(
            get: { vm.isPartyMode },
            set: { _ in vm.togglePartyMode() }
        )) {
            Label("Party Mode", systemImage: vm.isPartyMode ? "party.popper.fill" : "party.popper")
        }
        .toggleStyle(.switch)
        .disabled(vm.isBusyGrouping || !vm.canTogglePartyMode)
    }

    private var routinesRow: some View {
        HStack(spacing: 8) {
            Button {
                vm.pauseAll()
            } label: {
                Label("Pause All", systemImage: "pause.circle")
            }
            Button {
                vm.goodnight()
            } label: {
                Label("Goodnight", systemImage: "moon.zzz")
            }
            if let tvRoom = vm.tvRooms.first {
                Button {
                    vm.movieNight(in: tvRoom)
                } label: {
                    Label("Movie", systemImage: "popcorn")
                }
                .help("Movie night in \(tvRoom.name): switch it to TV on its own")
            }
            Spacer()
        }
        .controlSize(.small)
        .font(.caption)
        .disabled(vm.allDevices.isEmpty)
    }

    private var footer: some View {
        HStack {
            Button("Open Sonos Remote") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            SettingsLink {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .font(.caption)
    }
}

/// A multi-room group: one play/pause and one volume slider for the whole
/// group, then each room's own slider underneath.
private struct MenuBarGroupSection: View {
    @EnvironmentObject var vm: SonosViewModel
    let group: SonosGroup

    private var isPlaying: Bool { vm.transportStates[group.id] == .playing }
    private var track: TrackInfo? { vm.nowPlaying[group.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button {
                        vm.togglePlayPause(group)
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help("Play/pause the group")

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Group · \(group.members.count) rooms")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let track, !track.title.isEmpty {
                            Text(track.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                VolumeSlider(
                    value: vm.groupVolumes[group.id] ?? 0,
                    isMuted: vm.groupMutes[group.id] ?? false,
                    onCommit: { vm.setGroupVolume(group, to: $0) },
                    onToggleMute: { vm.toggleGroupMute(group) },
                    compact: true
                )
            }
            ForEach(group.members.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { device in
                MenuBarRoomRow(device: device, showsTransport: false)
                    .padding(.leading, 14)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MenuBarRoomRow: View {
    @EnvironmentObject var vm: SonosViewModel
    let device: SonosDevice
    /// Off for rooms inside a group section, which has the shared controls.
    let showsTransport: Bool

    private var group: SonosGroup? { vm.group(containing: device) }
    private var isPlaying: Bool { group.flatMap { vm.transportStates[$0.id] } == .playing }
    private var track: TrackInfo? { vm.trackInfo(for: device) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if showsTransport {
                    Button {
                        if let group { vm.togglePlayPause(group) }
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help("Play/pause \(device.name)")
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(device.name)
                        .font(showsTransport ? .subheadline : .caption)
                        .lineLimit(1)
                    if showsTransport, let track, !track.title.isEmpty {
                        Text(track.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            VolumeSlider(
                value: vm.deviceVolumes[device.uuid] ?? 0,
                isMuted: vm.deviceMutes[device.uuid] ?? false,
                onCommit: { vm.setDeviceVolume(device, to: $0) },
                onToggleMute: { vm.toggleDeviceMute(device) },
                compact: true
            )
        }
    }
}
