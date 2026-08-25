import EnoughBoxPluginSDK
import Foundation

final class HostServicesImpl: NSObject, HostServices, HostServicesHotkeys {
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
}
