import SwiftUI
import AppKit

/// Compact popover shown when the menu bar icon is clicked: quick per-room
/// volume, a play/pause per room ("select where to play"), and Party Mode.
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
            Divider()
            recentlyPlayedSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .task { await vm.refreshTopology() }
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
                    ForEach(vm.allDevicesSorted) { device in
                        MenuBarRoomRow(device: device)
                    }
                }
            }
            .frame(maxHeight: 260)
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
        .disabled(vm.isBusyGrouping || vm.groups.count < 2 && !vm.isPartyMode)
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

private struct MenuBarRoomRow: View {
    @EnvironmentObject var vm: SonosViewModel
    let device: SonosDevice

    private var group: SonosGroup? { vm.group(containing: device) }
    private var isPlaying: Bool { group.flatMap { vm.transportStates[$0.id] } == .playing }
    private var volume: Double { Double(vm.deviceVolumes[device.uuid] ?? 0) }
    private var track: TrackInfo? { vm.trackInfo(for: device) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    if let group { vm.togglePlayPause(group) }
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Play/pause \(device.name)")

                VStack(alignment: .leading, spacing: 0) {
                    Text(device.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    if let track, !track.title.isEmpty {
                        Text(track.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text("\(Int(volume))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { volume },
                    set: { vm.setDeviceVolume(device, to: Int($0)) }
                ), in: 0...100, step: 1)
                Image(systemName: "speaker.wave.3.fill").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
