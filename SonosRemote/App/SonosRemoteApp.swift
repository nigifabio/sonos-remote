import SwiftUI

@main
struct SonosRemoteApp: App {
    @StateObject private var viewModel = SonosViewModel()
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.system.rawValue

    private var colorScheme: ColorScheme? {
        (AppTheme(rawValue: themeRaw) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 820, minHeight: 560)
                .preferredColorScheme(colorScheme)
                .onAppear { viewModel.start() }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(viewModel)
                .preferredColorScheme(colorScheme)
        } label: {
            Image("TrayIcon")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .preferredColorScheme(colorScheme)
        }
    }
}
