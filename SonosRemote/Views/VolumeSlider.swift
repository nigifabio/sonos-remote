import SwiftUI

/// A volume slider with a mute button, shared by the main window and the
/// menu bar tray. Updates its displayed value locally on every drag tick,
/// but only fires `onCommit` once — when the drag ends. Firing a network
/// call on every intermediate value (the original approach) spawned dozens
/// of concurrent SetVolume requests per drag; they could race and land out
/// of order over the network, so the volume didn't reliably end up where
/// you actually dragged it to.
struct VolumeSlider: View {
    @Binding var value: Double
    let isMuted: Bool
    let onCommit: (Int) -> Void
    let onToggleMute: () -> Void

    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(compact ? .caption2 : .body)
                    .foregroundStyle(isMuted ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .help(isMuted ? "Unmute" : "Mute")

            Slider(value: $value, in: 0...100, step: 1, onEditingChanged: { editing in
                if !editing { onCommit(Int(value)) }
            })

            if !compact {
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            Text("\(Int(value))")
                .font(compact ? .caption2.monospacedDigit() : .caption.monospacedDigit())
                .foregroundStyle(compact ? .secondary : .primary)
                .frame(width: compact ? 20 : 28, alignment: .trailing)
        }
    }
}
