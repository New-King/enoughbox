import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let translateSelection = Self("com.enoughbox.translate.selection")
}

enum HotkeyCatalog {
    static let translateSelectionID = "com.enoughbox.translate.selection"
}

enum HotkeyCatalogHost {
    static func shortcutName(for identifier: String) -> KeyboardShortcuts.Name? {
        identifier == HotkeyCatalog.translateSelectionID ? .translateSelection : nil
    }

    static func recorderName(forToolID toolID: String) -> KeyboardShortcuts.Name? {
        toolID == "com.enoughbox.translate" ? .translateSelection : nil
    }
}

@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var handlers: [String: () -> Void] = [:]
    private var listeningNames: Set<KeyboardShortcuts.Name> = []
    private var hotkeysSuspendedForRecording = false

    private init() {}

    func register(_ identifier: String, handler: @escaping () -> Void) {
        guard let name = HotkeyCatalogHost.shortcutName(for: identifier) else { return }

        handlers[identifier] = handler
        installListenerIfNeeded(for: name)
    }

    func unregister(_ identifier: String) {
        guard let name = HotkeyCatalogHost.shortcutName(for: identifier) else { return }

        handlers.removeValue(forKey: identifier)
        guard !handlers.contains(where: { HotkeyCatalogHost.shortcutName(for: $0.key) == name }) else {
            return
        }
        KeyboardShortcuts.disable(name)
    }

    func clearShortcut(forToolID toolID: String) {
        guard let name = HotkeyCatalogHost.recorderName(forToolID: toolID) else { return }
        KeyboardShortcuts.setShortcut(nil, for: name)
    }

    func hasShortcutConflict(
        _ shortcut: KeyboardShortcuts.Shortcut,
        excluding name: KeyboardShortcuts.Name
    ) -> Bool {
        listeningNames.contains { candidate in
            candidate != name && KeyboardShortcuts.getShortcut(for: candidate) == shortcut
        }
    }

    func suspendForShortcutRecording() {
        hotkeysSuspendedForRecording = true
        guard !listeningNames.isEmpty else { return }
        KeyboardShortcuts.disable(Array(listeningNames))
    }

    func resumeAfterShortcutRecording() {
        guard hotkeysSuspendedForRecording else { return }
        hotkeysSuspendedForRecording = false
        guard !listeningNames.isEmpty else { return }
        KeyboardShortcuts.enable(Array(listeningNames))
    }

    private func installListenerIfNeeded(for name: KeyboardShortcuts.Name) {
        if listeningNames.contains(name) {
            if hotkeysSuspendedForRecording {
                KeyboardShortcuts.disable(name)
            } else {
                KeyboardShortcuts.enable(name)
            }
            return
        }
        listeningNames.insert(name)

        KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
            guard let self else { return }
            for (identifier, handler) in self.handlers {
                guard HotkeyCatalogHost.shortcutName(for: identifier) == name else { continue }
                handler()
            }
        }
        if hotkeysSuspendedForRecording {
            KeyboardShortcuts.disable(name)
        }
    }
}
