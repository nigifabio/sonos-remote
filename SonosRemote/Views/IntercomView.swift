import SwiftUI
import CoreAudio

struct IntercomView: View {
    @EnvironmentObject var vm: SonosViewModel
    @ObservedObject var intercom: IntercomService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDeviceIDs: Set<String> = []
    @State private var micGranted = true

    private var targets: [SonosDevice] {
        vm.allDevices.filter { selectedDeviceIDs.contains($0.uuid) }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Intercom")
                .font(.title2.bold())
            Text("Hold the button, speak, then release to announce it in the selected room(s).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            micPicker
            roomPicker
            pushToTalkButton

            if intercom.isBroadcasting {
                ProgressView("Playing announcement…")
            }
            if !micGranted {
                Text("Microphone access is required. Grant it in System Settings ▸ Privacy & Security ▸ Microphone.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            if let error = intercom.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 380)
        .task {
            micGranted = await intercom.requestMicPermission()
            intercom.refreshMics()
            if selectedDeviceIDs.isEmpty {
                selectedDeviceIDs = Set(vm.allDevices.map(\.uuid))
            }
        }
    }

    private var micPicker: some View {
        HStack {
            Text("Microphone:")
                .font(.subheadline.bold())
            Picker("", selection: $intercom.selectedMicID) {
                Text("System Default").tag(AudioDeviceID?.none)
                ForEach(intercom.availableMics) { mic in
                    Text(mic.name).tag(AudioDeviceID?.some(mic.id))
                }
            }
            .labelsHidden()
            Button {
                intercom.refreshMics()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Rescan microphones")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var roomPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Announce to:")
                .font(.subheadline.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(vm.allDevices) { device in
                        Toggle(device.name, isOn: Binding(
                            get: { selectedDeviceIDs.contains(device.uuid) },
                            set: { on in
                                if on { selectedDeviceIDs.insert(device.uuid) }
                                else { selectedDeviceIDs.remove(device.uuid) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 140)
            HStack {
                Button("All") { selectedDeviceIDs = Set(vm.allDevices.map(\.uuid)) }
                Button("None") { selectedDeviceIDs = [] }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pushToTalkButton: some View {
        Circle()
            .fill(intercom.isRecording ? Color.red : Color.accentColor)
            .frame(width: 96, height: 96)
            .overlay(
                Image(systemName: "mic.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
            )
            .scaleEffect(intercom.isRecording ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: intercom.isRecording)
            .opacity(micGranted && !targets.isEmpty ? 1 : 0.4)
            .onLongPressGesture(minimumDuration: 0.05, maximumDistance: 50, pressing: { pressing in
                guard micGranted, !targets.isEmpty, !intercom.isBroadcasting else { return }
                if pressing {
                    if !intercom.isRecording { intercom.startRecording() }
                } else if intercom.isRecording {
                    intercom.stopAndBroadcast(to: targets)
                }
            }, perform: {})
            .help(targets.isEmpty ? "Select at least one room" : "Hold to talk")
    }
}
