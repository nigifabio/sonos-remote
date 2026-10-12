import SwiftUI

struct GroupDetailView: View {
    @EnvironmentObject var vm: SonosViewModel
    let group: SonosGroup
    @State private var eqTarget: SonosDevice?

    private var track: TrackInfo { vm.nowPlaying[group.id] ?? TrackInfo() }
    private var isPlaying: Bool { vm.transportStates[group.id] == .playing }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                generalVolumeSection
                nowPlayingCard
                if group.members.count > 1 {
                    perDeviceVolumeSection
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(group.name)
        .sheet(item: $eqTarget) { device in
            EQView(device: device)
                .environmentObject(vm)
        }
    }

    private var nowPlayingCard: some View {
        VStack(spacing: 16) {
            albumArt
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 6)

            VStack(spacing: 4) {
                Text(track.title.isEmpty ? "Nothing playing" : track.title)
                    .font(.title3.bold())
                    .lineLimit(1)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !track.album.isEmpty {
                    Text(track.album)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            if track.durationSeconds > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    SeekBar(
                        position: vm.position(in: group, at: context.date),
                        duration: track.durationSeconds,
                        onSeek: { vm.seek(group, toSeconds: $0) }
                    )
                }
                .frame(maxWidth: 360)
            }

            HStack(spacing: 22) {
                Button { vm.toggleShuffle(group) } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(playMode.shuffle ? Color.accentColor : Color.secondary)
                }
                .font(.body)
                .disabled(!hasQueueControls)
                .help(playMode.shuffle ? "Shuffle is on" : "Shuffle is off")
                .accessibilityLabel("Shuffle")
                .accessibilityValue(playMode.shuffle ? "On" : "Off")

                Button { vm.previous(group) } label: {
                    Image(systemName: "backward.fill")
                }
                .accessibilityLabel("Previous track")
                Button { vm.togglePlayPause(group) } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                Button { vm.next(group) } label: {
                    Image(systemName: "forward.fill")
                }
                .accessibilityLabel("Next track")

                Button { vm.cycleRepeat(group) } label: {
                    Image(systemName: playMode.repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundStyle(playMode.repeatMode == .off ? Color.secondary : Color.accentColor)
                }
                .font(.body)
                .disabled(!hasQueueControls)
                .help(repeatHelp)
                .accessibilityLabel("Repeat")
                .accessibilityValue(repeatHelp)
            }
            .font(.title2)
            .buttonStyle(.borderless)

            if !inputSources.isEmpty {
                Menu {
                    ForEach(inputSources, id: \.title) { source in
                        Button(source.title, systemImage: source.icon, action: source.action)
                    }
                } label: {
                    Label("Source", systemImage: "arrow.left.arrow.right")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Play a TV or line-in input")
            }
        }
    }

    private var playMode: PlayMode { vm.playModes[group.id] ?? PlayMode() }

    /// Shuffle and repeat only mean something for a track from a queue —
    /// not for radio, TV or line-in, which report no duration.
    private var hasQueueControls: Bool { track.durationSeconds > 0 }

    private var repeatHelp: String {
        switch playMode.repeatMode {
        case .off: return "Repeat is off"
        case .all: return "Repeating the queue"
        case .one: return "Repeating this track"
        }
    }

    private struct InputSource {
        let title: String
        let icon: String
        let action: () -> Void
    }

    private var inputSources: [InputSource] {
        group.members.flatMap { device -> [InputSource] in
            var sources: [InputSource] = []
            if vm.hasTVInput(device) {
                sources.append(InputSource(title: "TV — \(device.name)", icon: "tv") { vm.switchToTV(device) })
            }
            if vm.hasLineIn(device) {
                sources.append(InputSource(title: "Line-In — \(device.name)", icon: "cable.connector") { vm.switchToLineIn(device) })
            }
            return sources
        }
    }

    @ViewBuilder
    private var albumArt: some View {
        if let url = track.albumArtURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    placeholderArt
                }
            }
        } else {
            placeholderArt
        }
    }

    private var placeholderArt: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.quaternary)
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }

    private var generalVolumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(group.members.count > 1 ? "Group Volume" : "Volume", systemImage: "speaker.wave.2.fill")
                    .font(.headline)
                Spacer()
                if let coordinator = group.coordinator {
                    eqButton(for: coordinator)
                }
            }
            VolumeSlider(
                value: vm.groupVolumes[group.id] ?? 0,
                isMuted: vm.groupMutes[group.id] ?? false,
                onCommit: { vm.setGroupVolume(group, to: $0) },
                onToggleMute: { vm.toggleGroupMute(group) }
            )
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var perDeviceVolumeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Individual Rooms", systemImage: "hifispeaker.fill")
                .font(.headline)
            ForEach(group.members) { device in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(device.name)
                            .font(.subheadline)
                        Spacer()
                        eqButton(for: device)
                    }
                    VolumeSlider(
                        value: vm.deviceVolumes[device.uuid] ?? 0,
                        isMuted: vm.deviceMutes[device.uuid] ?? false,
                        onCommit: { vm.setDeviceVolume(device, to: $0) },
                        onToggleMute: { vm.toggleDeviceMute(device) }
                    )
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func eqButton(for device: SonosDevice) -> some View {
        Button {
            eqTarget = device
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .buttonStyle(.borderless)
        .help("Bass, treble, and loudness for \(device.name)")
    }
}
