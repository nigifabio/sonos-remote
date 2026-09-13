import SwiftUI

/// Shows what's been played recently. Sonos itself doesn't expose play
/// history over UPnP — this is built locally from track-change events plus
/// whatever this app itself has told a room to play (see
/// `SonosViewModel.playbackHistory`).
struct HistoryView: View {
    @EnvironmentObject var vm: SonosViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recently Played").font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            Divider()

            if vm.playbackHistory.isEmpty {
                ContentUnavailableView(
                    "Nothing played yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Play something and it'll show up here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        highlights
                        Divider()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("All Recent").font(.subheadline.bold())
                            ForEach(vm.playbackHistory) { entry in
                                HistoryRow(entry: entry)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 420, height: 560)
    }

    @ViewBuilder
    private var highlights: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let last = vm.lastPlayed {
                highlightRow(icon: "music.note", label: "Last Song", entry: last)
            }
            if let playlist = vm.lastSpotifyPlaylist {
                highlightRow(icon: "music.note.list", label: "Last Spotify Playlist", entry: playlist, showPlaylistName: true)
            } else if let track = vm.lastSpotifyTrack {
                highlightRow(icon: "music.note.list", label: "Last Spotify Track", entry: track)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "music.note.list").foregroundStyle(.secondary).frame(width: 20)
                    Text("No Spotify playback seen yet").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func highlightRow(icon: String, label: String, entry: PlaybackHistoryEntry, showPlaylistName: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if showPlaylistName, let sourceLabel = entry.sourceLabel {
                    Text(sourceLabel).font(.headline)
                    Text("\(entry.title) — \(entry.artist)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(entry.title).font(.headline)
                    if !entry.artist.isEmpty {
                        Text(entry.artist).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("\(entry.groupName) · \(entry.date, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct HistoryRow: View {
    let entry: PlaybackHistoryEntry

    var body: some View {
        HStack(spacing: 10) {
            serviceBadge
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.sourceLabel ?? entry.title).lineLimit(1)
                Text(entry.sourceLabel != nil ? "\(entry.title) — \(entry.artist)" : entry.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(entry.groupName).font(.caption2).foregroundStyle(.secondary)
                Text(entry.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var serviceBadge: some View {
        Group {
            switch entry.service {
            case .spotify: Image(systemName: "music.note.list").foregroundStyle(.green)
            case .appleMusic: Image(systemName: "music.note").foregroundStyle(.pink)
            case .local: Image(systemName: "house.fill").foregroundStyle(.secondary)
            case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
        .frame(width: 20)
    }
}
