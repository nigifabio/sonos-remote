import SwiftUI
import ServiceManagement
import AVFoundation
import AppKit

struct SettingsView: View {
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.system.rawValue
    @State private var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    private var theme: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: themeRaw) ?? .system },
            set: { themeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: theme) {
                    ForEach(AppTheme.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Permissions") {
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    detail: "Used by the Intercom feature to record announcements.",
                    statusText: micStatusText,
                    statusColor: micStatusColor,
                    actionTitle: micActionTitle,
                    action: handleMicAction
                )
                permissionRow(
                    icon: "network",
                    title: "Local Network",
                    detail: "Used to discover and control your Sonos speakers on the LAN.",
                    statusText: "Manage in System Settings",
                    statusColor: .secondary,
                    actionTitle: "Open Settings",
                    action: { openSystemSettings(pane: "Privacy_LocalNetwork") }
                )
                Text("macOS doesn't let apps change these directly — use the buttons above to jump to System Settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Start Sonos Remote at login", isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { setLaunchAtLogin($0) }
                ))
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("About") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "hifispeaker.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sonos Remote")
                                .font(.headline)
                            Text("Version 1.0")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Made by Fabio Nigi")
                            .font(.subheadline)
                        Link("nigifabio@gmail.com", destination: URL(string: "mailto:nigifabio@gmail.com")!)
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 560)
        .onAppear {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    @ViewBuilder
    private func permissionRow(
        icon: String, title: String, detail: String,
        statusText: String, statusColor: Color,
        actionTitle: String, action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Text(statusText).font(.caption2).foregroundStyle(statusColor)
            }
            Spacer()
            Button(actionTitle, action: action)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private var micStatusText: String {
        switch micStatus {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted by system policy"
        case .notDetermined: return "Not requested yet"
        @unknown default: return "Unknown"
        }
    }

    private var micStatusColor: Color {
        switch micStatus {
        case .authorized: return .green
        case .denied, .restricted: return .red
        case .notDetermined: return .secondary
        @unknown default: return .secondary
        }
    }

    private var micActionTitle: String {
        micStatus == .notDetermined ? "Request Access" : "Open Settings"
    }

    private func handleMicAction() {
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                }
            }
        } else {
            openSystemSettings(pane: "Privacy_Microphone")
        }
    }

    private func openSystemSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Couldn't update Login Items: \(error.localizedDescription)"
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
