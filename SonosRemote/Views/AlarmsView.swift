import SwiftUI

struct AlarmsView: View {
    @EnvironmentObject var vm: SonosViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var alarms: [SonosAlarm] = []
    @State private var isLoading = false
    @State private var newAlarmTime = Date()
    @State private var newAlarmRoomUUID = ""
    @State private var sleepTimerMinutes: Double = 0
    @State private var sleepTimerDevice: SonosDevice?

    private var bootstrapDevice: SonosDevice? { vm.allDevices.first }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Alarms & Sleep Timer").font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sleepTimerSection
                    Divider()
                    alarmsSection
                    Divider()
                    addAlarmSection
                }
                .padding()
            }
        }
        .frame(width: 420, height: 560)
        .task { await load() }
    }

    private var sleepTimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep Timer").font(.subheadline.bold())
            Picker("Room", selection: Binding(
                get: { sleepTimerDevice?.uuid ?? "" },
                set: { uuid in sleepTimerDevice = vm.allDevices.first { $0.uuid == uuid } }
            )) {
                Text("Select a room").tag("")
                ForEach(vm.allDevicesSorted) { device in Text(device.name).tag(device.uuid) }
            }
            HStack {
                Slider(value: $sleepTimerMinutes, in: 0...120, step: 5)
                Text(sleepTimerMinutes == 0 ? "Off" : "\(Int(sleepTimerMinutes)) min")
                    .font(.caption.monospacedDigit())
                    .frame(width: 50, alignment: .trailing)
            }
            Button("Set Sleep Timer") { Task { await setSleepTimer() } }
                .disabled(sleepTimerDevice == nil)
        }
    }

    private var alarmsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alarms").font(.subheadline.bold())
            if isLoading {
                ProgressView()
            } else if alarms.isEmpty {
                Text("No alarms configured.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(alarms) { alarm in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alarm.startTime).font(.body.monospacedDigit())
                            Text("\(roomName(for: alarm.roomUUID)) · \(alarm.recurrence)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { alarm.enabled },
                            set: { toggle(alarm, enabled: $0) }
                        ))
                        .labelsHidden()
                        Button {
                            delete(alarm)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var addAlarmSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Alarm").font(.subheadline.bold())
            DatePicker("Time", selection: $newAlarmTime, displayedComponents: .hourAndMinute)
            Picker("Room", selection: $newAlarmRoomUUID) {
                Text("Select a room").tag("")
                ForEach(vm.allDevicesSorted) { device in Text(device.name).tag(device.uuid) }
            }
            Text("Rings with the built-in Sonos chime.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Add Alarm") { Task { await addAlarm() } }
                .disabled(newAlarmRoomUUID.isEmpty)
        }
    }

    private func roomName(for uuid: String) -> String {
        vm.allDevices.first { $0.uuid == uuid }?.name ?? "Unknown room"
    }

    private func load() async {
        guard let device = bootstrapDevice else { return }
        isLoading = true
        alarms = (try? await SonosController.listAlarms(device)) ?? []
        isLoading = false
    }

    private func toggle(_ alarm: SonosAlarm, enabled: Bool) {
        guard let device = vm.allDevices.first(where: { $0.uuid == alarm.roomUUID }) ?? bootstrapDevice else { return }
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) { alarms[index].enabled = enabled }
        Task { try? await SonosController.setAlarmEnabled(alarm, enabled: enabled, on: device) }
    }

    private func delete(_ alarm: SonosAlarm) {
        guard let device = bootstrapDevice else { return }
        alarms.removeAll { $0.id == alarm.id }
        Task { try? await SonosController.deleteAlarm(alarm, on: device) }
    }

    private func addAlarm() async {
        guard let device = vm.allDevices.first(where: { $0.uuid == newAlarmRoomUUID }) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeString = formatter.string(from: newAlarmTime)
        try? await SonosController.createAlarm(device: device, startTime: timeString)
        await load()
    }

    private func setSleepTimer() async {
        guard let device = sleepTimerDevice else { return }
        let seconds = Int(sleepTimerMinutes) * 60
        try? await SonosController.setSleepTimer(device, seconds: seconds > 0 ? seconds : nil)
    }
}
