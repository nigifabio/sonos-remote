import SwiftUI

/// A volume slider with a mute button, shared by the main window and the
/// menu bar tray.
///
/// While a drag is in progress the thumb follows a value held here, not the
/// model's: speakers keep reporting their volume (live events, the periodic
/// poll) during a drag, and letting those reports drive the thumb makes it
/// jump under the pointer. The speaker is told once, when the drag ends —
/// sending every intermediate value spawned dozens of concurrent SetVolume
/// requests that could land out of order.
struct VolumeSlider: View {
    let value: Int
    let isMuted: Bool
    let onCommit: (Int) -> Void
    let onToggleMute: () -> Void

    var compact: Bool = false

    @State private var dragValue: Double?
    @State private var isEditing = false

    private var shownValue: Double { dragValue ?? Double(value) }

    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(compact ? .caption2 : .body)
                    .foregroundStyle(isMuted ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .help(isMuted ? "Unmute" : "Mute")

            Slider(value: Binding(get: { shownValue }, set: { newValue in
                if isEditing {
                    dragValue = newValue
                } else {
                    // Keyboard and accessibility adjustments change the value
                    // without a drag session, so there is no "drag ended".
                    onCommit(Int(newValue.rounded()))
                }
            // No `step:` — a stepped slider draws a tick mark per step, and
            // a hundred of them turn the track into a zigzag.
            }), in: 0...100, onEditingChanged: { editing in
                isEditing = editing
                if editing {
                    if dragValue == nil { dragValue = Double(value) }
                } else if let final = dragValue {
                    dragValue = nil
                    onCommit(Int(final.rounded()))
                }
            })

            if !compact {
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            Text("\(Int(shownValue.rounded()))")
                .font(compact ? .caption2.monospacedDigit() : .caption.monospacedDigit())
                .foregroundStyle(compact ? .secondary : .primary)
                .frame(width: compact ? 20 : 28, alignment: .trailing)
        }
    }
}
