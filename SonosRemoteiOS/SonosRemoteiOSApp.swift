import SwiftUI

@main
struct SonosRemoteiOSApp: App {
    @StateObject private var viewModel = SonosViewModel()
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.system.rawValue

    private var colorScheme: ColorScheme? {
        (AppTheme(rawValue: themeRaw) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup {
            iOSContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(colorScheme)
                .onAppear { viewModel.start() }
        }
    }
}
