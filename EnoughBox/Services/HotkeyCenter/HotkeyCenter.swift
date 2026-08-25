import EnoughBoxPluginSDK
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let sampleTrigger = Self("com.enoughbox.sample.trigger")
}

enum HotkeyCatalogHost {
    static func shortcutName(for identifier: String) -> KeyboardShortcuts.Name? {
        switch identifier {
        case EnoughBoxPluginSDK.HotkeyCatalog.sampleTriggerID:
            return .sampleTrigger
        default:
            return nil
        }
    }

    static func recorderName(forPluginID pluginID: String) -> KeyboardShortcuts.Name? {
        switch pluginID {
        case "com.enoughbox.sample":
            return .sampleTrigger
        default:
            return nil
        }
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

    func debugDescription(forPluginID pluginID: String) -> String {
        guard let name = HotkeyCatalogHost.recorderName(forPluginID: pluginID),
              let shortcut = KeyboardShortcuts.getShortcut(for: name) else {
            return "No shortcut saved for \(pluginID)"
        }
        return "Shortcut for \(pluginID): \(shortcut.description)"
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

    /// Removes persisted shortcuts when a plugin is uninstalled so reinstall starts clean.
    func clearSavedShortcuts(forPluginID pluginID: String) {
        guard let name = HotkeyCatalogHost.recorderName(forPluginID: pluginID) else { return }

        for identifier in handlers.keys where HotkeyCatalogHost.shortcutName(for: identifier) == name {
            unregister(identifier)
        }

        name.shortcut = nil
        listeningNames.remove(name)
    }

    private func installListenerIfNeeded(for name: KeyboardShortcuts.Name) {
        guard !listeningNames.contains(name) else { return }
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
