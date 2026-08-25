import EnoughBoxPluginSDK
import Foundation

final class HostServicesImpl: NSObject, HostServices, HostServicesHotkeys, HostServicesSelection, HostServicesClipboard {
    private let toastHandler: (String) -> Void

    init(toastHandler: @escaping (String) -> Void) {
        self.toastHandler = toastHandler
    }

    func showToast(_ message: String) {
        toastHandler(message)
    }

    func registerHotkey(_ identifier: String, handler: @escaping () -> Void) {
        Task { @MainActor in
            HotkeyCenter.shared.register(identifier, handler: handler)
        }
    }

    func unregisterHotkey(_ identifier: String) {
        Task { @MainActor in
            HotkeyCenter.shared.unregister(identifier)
        }
    }

    func isAccessibilityTrusted() -> Bool {
        SelectionCapture.isAccessibilityTrusted()
    }

    func requestAccessibilityTrust() {
        SelectionCapture.requestAccessibilityTrust()
    }

    func currentSelectedText() -> String {
        SelectionCapture.currentSelectedText()
    }

    func textForTranslation() -> String {
        SelectionCapture.textForTranslation()
    }

    func lastSelectionDebugLine() -> String {
        SelectionCapture.lastDebugLine
    }

    func lastSelectionLogPath() -> String {
        SelectionCapture.lastLogPath
    }

    func clipboardText() -> String {
        SelectionCapture.clipboardText()
    }
}
