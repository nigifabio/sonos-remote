import SwiftUI

struct iOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.system.rawValue

    private var theme: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: themeRaw) ?? .system },
            set: { themeRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
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
                    Button("Open Settings App") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Text("Local Network access is required to find and control your Sonos speakers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "hifispeaker.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sonos Remote").font(.headline)
                                Text("Version 1.0").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        Text("Made by Fabio Nigi").font(.subheadline)
                        Link("nigifabio@gmail.com", destination: URL(string: "mailto:nigifabio@gmail.com")!)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
