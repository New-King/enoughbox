import AppKit
import KeyboardShortcuts
import SwiftUI

@main
struct EnoughBoxApp: App {
    @NSApplicationDelegateAdaptor(EnoughBoxAppDelegate.self) private var appDelegate
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
                .frame(minWidth: 720, minHeight: 400)
        }
        .defaultSize(width: 900, height: 560)
        .windowResizability(.contentMinSize)
        .commands {
            // WindowGroup 默认绑定 ⌘N「新建窗口」；工具箱只需单窗口。
            CommandGroup(replacing: .newItem) { }
        }
    }
}

final class EnoughBoxAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidBecomeActive(_ notification: Notification) {
        InputRecovery.recoverIfNeeded()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let panel = sender.keyWindow as? NSPanel {
            panel.close()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let mainWindows = sender.windows.filter { !($0 is NSPanel) }
        if let window = mainWindows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            mainWindows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
