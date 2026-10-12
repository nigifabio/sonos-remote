import SwiftUI

/// Track position with scrubbing. Like `VolumeSlider`, the thumb follows a
/// value held here while it is being dragged (the position ticks forward
/// every second underneath), and the speaker is told once, on release.
struct SeekBar: View {
    let position: Int
    let duration: Int
    let onSeek: (Int) -> Void

    @State private var dragValue: Double?
    @State private var isEditing = false

    private var shown: Double { dragValue ?? Double(min(position, duration)) }

    var body: some View {
        VStack(spacing: 2) {
            Slider(value: Binding(get: { shown }, set: { newValue in
                if isEditing { dragValue = newValue } else { onSeek(Int(newValue)) }
            }), in: 0...Double(max(duration, 1)), onEditingChanged: { editing in
                isEditing = editing
                if editing {
                    if dragValue == nil { dragValue = Double(position) }
                } else if let final = dragValue {
                    dragValue = nil
                    onSeek(Int(final))
                }
            })
            .controlSize(.small)
            HStack {
                Text(Self.clock(Int(shown)))
                Spacer()
                Text(Self.clock(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    /// "3:07", or "1:02:03" from an hour up.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
