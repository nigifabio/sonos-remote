import SwiftUI
import CoreAudio

struct IntercomView: View {
    @EnvironmentObject var vm: SonosViewModel
    @ObservedObject var intercom: IntercomService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDeviceIDs: Set<String> = []
    @State private var micGranted = true
    @State private var typedMessage = ""
    @State private var isSpeaking = false

    private var targets: [SonosDevice] {
        vm.allDevices.filter { selectedDeviceIDs.contains($0.uuid) }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Intercom")
                .font(.title2.bold())
            Text("Hold the button and speak, or type a message to have it read out, in the selected rooms.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            micPicker
            roomPicker
            pushToTalkButton
            typedMessageRow

            if intercom.isBroadcasting || isSpeaking {
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
            // The demo never records, so it never asks for the microphone.
            micGranted = vm.isDemo ? true : await intercom.requestMicPermission()
            if !vm.isDemo { intercom.refreshMics() }
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

    private var typedMessageRow: some View {
        HStack {
            TextField("Type a message to read out", text: $typedMessage)
                .textFieldStyle(.roundedBorder)
                .onSubmit(speakTypedMessage)
            Button("Speak", action: speakTypedMessage)
                .disabled(typedMessage.trimmingCharacters(in: .whitespaces).isEmpty || targets.isEmpty || isSpeaking || intercom.isBroadcasting)
        }
    }

    private func speakTypedMessage() {
        let message = typedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !targets.isEmpty, !isSpeaking else { return }
        let rooms = targets
        isSpeaking = true
        intercom.lastError = nil
        Task {
            do {
                _ = try await vm.announce(message, in: rooms)
                typedMessage = ""
            } catch {
                intercom.lastError = SonosViewModel.describe(error)
            }
            isSpeaking = false
        }
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
                    intercom.stopAndBroadcast(to: targets, groups: vm.groups)
                }
            }, perform: {})
            .help(targets.isEmpty ? "Select at least one room" : "Hold to talk")
    }
}
