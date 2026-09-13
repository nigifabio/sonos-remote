import WidgetKit
import SwiftUI

struct SonosEntry: TimelineEntry {
    let date: Date
    let room: RoomEntity?
    let roomName: String
    let title: String
    let artist: String
    let isPlaying: Bool
    let volume: Int
    let isPartyMode: Bool
}

struct SonosTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SonosEntry {
        SonosEntry(date: Date(), room: nil, roomName: "Sonos", title: "Nothing playing", artist: "", isPlaying: false, volume: 30, isPartyMode: false)
    }

    func snapshot(for configuration: SonosWidgetConfigurationIntent, in context: Context) async -> SonosEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SonosWidgetConfigurationIntent, in context: Context) async -> Timeline<SonosEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(Date().addingTimeInterval(5 * 60)))
    }

    private func entry(for configuration: SonosWidgetConfigurationIntent) -> SonosEntry {
        let snapshot = WidgetSharedStore.read()
        guard let room = configuration.room,
              let roomInfo = snapshot?.rooms.first(where: { $0.id == room.id }) else {
            return SonosEntry(
                date: Date(), room: configuration.room,
                roomName: configuration.room?.name ?? "Choose a room",
                title: "", artist: "", isPlaying: false, volume: 0,
                isPartyMode: snapshot?.isPartyMode ?? false
            )
        }
        let nowPlaying = snapshot?.nowPlayingByGroup[roomInfo.groupID]
        return SonosEntry(
            date: Date(), room: room, roomName: roomInfo.name,
            title: nowPlaying?.title ?? "Nothing playing",
            artist: nowPlaying?.artist ?? "",
            isPlaying: nowPlaying?.isPlaying ?? false,
            volume: roomInfo.volume,
            isPartyMode: snapshot?.isPartyMode ?? false
        )
    }
}

struct SonosWidgetView: View {
    let entry: SonosEntry

    var body: some View {
        if let room = entry.room {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.roomName)
                    .font(.headline)
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title.isEmpty ? "Nothing playing" : entry.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    if !entry.artist.isEmpty {
                        Text(entry.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 14) {
                    Button(intent: PreviousTrackIntent(room: room)) {
                        Image(systemName: "backward.fill")
                    }
                    Button(intent: PlayPauseIntent(room: room)) {
                        Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                    }
                    Button(intent: NextTrackIntent(room: room)) {
                        Image(systemName: "forward.fill")
                    }
                    Spacer()
                    Button(intent: AdjustVolumeIntent(room: room, delta: -5)) {
                        Image(systemName: "speaker.fill")
                    }
                    Text("\(entry.volume)")
                        .font(.caption2.monospacedDigit())
                        .frame(width: 20)
                    Button(intent: AdjustVolumeIntent(room: room, delta: 5)) {
                        Image(systemName: "speaker.wave.3.fill")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 15))

                Button(intent: TogglePartyModeIntent()) {
                    Label(entry.isPartyMode ? "Ungroup" : "Party Mode",
                          systemImage: entry.isPartyMode ? "party.popper.fill" : "party.popper")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
            .padding()
        } else {
            VStack(spacing: 6) {
                Image(systemName: "hifispeaker.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text("Choose a room")
                    .font(.caption)
                Text("Edit this widget to pick a Sonos room")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

struct SonosWidget: Widget {
    let kind = "SonosWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SonosWidgetConfigurationIntent.self, provider: SonosTimelineProvider()) { entry in
            SonosWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sonos Room")
        .description("Control one Sonos room: playback, volume, and Party Mode.")
        .supportedFamilies([.systemMedium])
    }
}
