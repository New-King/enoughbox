import KeyboardShortcuts
import SwiftUI

@main
struct EnoughBoxApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var appearance = AppearanceManager()

    init() {
        KeyboardShortcuts.isEnabled = true
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .environmentObject(appearance)
                .preferredColorScheme(appearance.mode.resolvedColorScheme)
                .designTokensProvider()
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
    }
}
