import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

private let recorderActiveNotification = Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange")

/// Host-managed shortcut row. Kept outside `ScrollView` so `RecorderCocoa` receives clicks.
struct PluginShortcutSettingsCard: View {
    @Environment(\.designTokens) private var tokens

    let shortcutName: KeyboardShortcuts.Name

    @State private var errorText: String?
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("plugin.sample.section.shortcut")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.inkFaint)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                Text("plugin.sample.shortcut.placeholder")
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.inkMuted)

                Spacer(minLength: 8)

                KeyboardShortcuts.Recorder(for: shortcutName)
                    .frame(width: 140)
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            Text("plugin.sample.shortcut.footer.active")
                .font(.system(size: 11))
                .foregroundStyle(tokens.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: recorderActiveNotification)) { notification in
            let isRecording = notification.userInfo?["isActive"] as? Bool ?? false
            if isRecording {
                startInvalidKeyMonitor()
            } else {
                stopInvalidKeyMonitor()
                errorText = nil
            }
        }
        .onDisappear {
            stopInvalidKeyMonitor()
        }
    }

    private func startInvalidKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Self.isDisallowedGlobalShortcut(event) {
                errorText = String(localized: "plugin.sample.shortcut.error.needsModifier")
            }
            return event
        }
    }

    private func stopInvalidKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// Matches KeyboardShortcuts.RecorderCocoa: bare Shift+key (and other modifier-less keys) cannot be global shortcuts.
    private static func isDisallowedGlobalShortcut(_ event: NSEvent) -> Bool {
        let primary: NSEvent.ModifierFlags = [.command, .control, .option]
        if !event.modifierFlags.intersection(primary).isEmpty {
            return false
        }
        if functionKeyCodes.contains(event.keyCode) {
            return false
        }
        switch event.keyCode {
        case UInt16(kVK_Escape), UInt16(kVK_Delete), UInt16(kVK_ForwardDelete):
            return false
        default:
            return true
        }
    }

    private static let functionKeyCodes: Set<UInt16> = Set([
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ].map(UInt16.init))
}
