import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let translateSelection = Self("com.enoughbox.translate.selection")
    static let screenshotRegion = Self("com.enoughbox.screenshot.region")
    static let clipboardPanel = Self("com.enoughbox.clipboard.panel")
}

enum HotkeyCatalog {
    static let translateSelectionID = "com.enoughbox.translate.selection"
    static let screenshotRegionID = "com.enoughbox.screenshot.region"
    static let clipboardPanelID = "com.enoughbox.clipboard.panel"
}

enum HotkeyCatalogHost {
    static func shortcutName(for identifier: String) -> KeyboardShortcuts.Name? {
        switch identifier {
        case HotkeyCatalog.translateSelectionID: .translateSelection
        case HotkeyCatalog.screenshotRegionID: .screenshotRegion
        case HotkeyCatalog.clipboardPanelID: .clipboardPanel
        default: nil
        }
    }

    static func recorderName(forToolID toolID: String) -> KeyboardShortcuts.Name? {
        switch toolID {
        case "com.enoughbox.translate": .translateSelection
        case "com.enoughbox.screenshot": .screenshotRegion
        case "com.enoughbox.clipboard": .clipboardPanel
        default: nil
        }
    }
}

@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var handlers: [String: () -> Void] = [:]
    private var listeningNames: Set<KeyboardShortcuts.Name> = []
    private var hotkeysSuspendedForRecording = false

    /// True while a shortcut recorder has paused global hotkeys.
    var isShortcutRecording: Bool { hotkeysSuspendedForRecording }

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
        guard !hotkeysSuspendedForRecording else { return }
        hotkeysSuspendedForRecording = true
        KeyboardShortcuts.isEnabled = false
        guard !listeningNames.isEmpty else { return }
        KeyboardShortcuts.disable(Array(listeningNames))
    }

    func resumeAfterShortcutRecording() {
        guard hotkeysSuspendedForRecording else { return }
        hotkeysSuspendedForRecording = false
        KeyboardShortcuts.isEnabled = true
        guard !listeningNames.isEmpty else { return }
        KeyboardShortcuts.enable(Array(listeningNames))
    }

    private func installListenerIfNeeded(for name: KeyboardShortcuts.Name) {
        if listeningNames.contains(name) {
            if !hotkeysSuspendedForRecording {
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
        if !hotkeysSuspendedForRecording {
            KeyboardShortcuts.enable(name)
        }
    }
}
