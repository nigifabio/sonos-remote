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

            HStack(spacing: 28) {
                Button { vm.previous(group) } label: {
                    Image(systemName: "backward.fill")
                }
                Button { vm.togglePlayPause(group) } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                }
                .buttonStyle(.plain)
                Button { vm.next(group) } label: {
                    Image(systemName: "forward.fill")
                }
            }
            .font(.title2)
            .buttonStyle(.borderless)
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
                value: Binding(
                    get: { Double(vm.groupVolumes[group.id] ?? 0) },
                    set: { vm.groupVolumes[group.id] = Int($0) }
                ),
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
                        value: Binding(
                            get: { Double(vm.deviceVolumes[device.uuid] ?? 0) },
                            set: { vm.deviceVolumes[device.uuid] = Int($0) }
                        ),
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
