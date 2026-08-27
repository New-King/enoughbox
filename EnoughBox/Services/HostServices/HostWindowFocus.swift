import AppKit

@MainActor
enum HostWindowFocus {
    /// Returns key status to the main app window after a floating panel session ends.
    static func returnToMainWindow() {
        let mainWindow = NSApp.windows.first { window in
            !(window is NSPanel) && window.isVisible && window.canBecomeKey
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow?.makeFirstResponder(nil)
    }
}
