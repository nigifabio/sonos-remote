import AppIntents

struct SonosShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayRoomIntent(),
            phrases: [
                "Play \(.applicationName) in \(\.$room)",
                "Play music in \(\.$room) with \(.applicationName)"
            ],
            shortTitle: "Play Room",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PauseRoomIntent(),
            phrases: ["Pause \(\.$room) with \(.applicationName)"],
            shortTitle: "Pause Room",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: PlayPauseRoomIntent(),
            phrases: ["Toggle play in \(\.$room) with \(.applicationName)"],
            shortTitle: "Play/Pause Room",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: NextTrackShortcutIntent(),
            phrases: ["Skip to the next track in \(\.$room) with \(.applicationName)"],
            shortTitle: "Next Track",
            systemImageName: "forward.fill"
        )
        AppShortcut(
            intent: SetRoomVolumeIntent(),
            phrases: ["Set \(\.$room) volume with \(.applicationName)"],
            shortTitle: "Set Volume",
            systemImageName: "speaker.wave.2.fill"
        )
        AppShortcut(
            intent: TogglePartyModeShortcutIntent(),
            phrases: [
                "Toggle party mode with \(.applicationName)",
                "Start a party with \(.applicationName)"
            ],
            shortTitle: "Party Mode",
            systemImageName: "party.popper.fill"
        )
    }
}
