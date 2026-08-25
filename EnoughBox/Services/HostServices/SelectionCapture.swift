import ApplicationServices
import AppKit
import Foundation

/// Reads selected text via Accessibility. If AX is empty, briefly sends Command-C and restores the clipboard.
/// Command-C is only used when Accessibility is already trusted. Library has no selection API; this is host-owned.
enum SelectionCapture {
    static func isAccessibilityTrusted() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        return canReadFocusedElement()
    }

    /// Do not show the system TCC sheet. It re-prompts even when Settings already lists this app as on
    /// (common with Xcode Debug / ad-hoc signing). The Settings toggle is the source of truth.
    static func requestAccessibilityTrust() {}

    static func clipboardText() -> String {
        let raw = NSPasteboard.general.string(forType: .string) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func currentSelectedText() -> String {
        let trimmedAX = axSelectedText()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedAX.isEmpty {
            return trimmedAX
        }
        return copySelectedTextViaPasteboard()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func canReadFocusedElement() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        return AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success
    }

    private static func axSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success,
            let focused
        else {
            return nil
        }

        let element = focused as! AXUIElement
        var selected: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selected
        ) == .success else {
            return nil
        }
        return selected as? String
    }

    private static func copySelectedTextViaPasteboard() -> String? {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let previousString = pasteboard.string(forType: .string)

        guard postCommandC() else { return nil }

        let deadline = Date().addingTimeInterval(0.2)
        while Date() < deadline {
            if pasteboard.changeCount != previousChangeCount {
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        guard pasteboard.changeCount != previousChangeCount else { return nil }
        let copied = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        if let previousString {
            pasteboard.setString(previousString, forType: .string)
        }

        return copied
    }

    private static func postCommandC() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyC: CGKeyCode = 8

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
