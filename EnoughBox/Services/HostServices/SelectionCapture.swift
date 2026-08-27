import ApplicationServices
import AppKit
import Foundation

enum SelectionCapture {
    static func hasAccessibilityTrust() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    static func textForTranslation() async -> String {
        await Task.detached(priority: .userInitiated) {
            captureTextForTranslation()
        }.value
    }

    private static func captureTextForTranslation() -> String {
        if let ax = axFocusedSelectedText() {
            return ax
        }

        switch copySelectedText() {
        case .copied(let copied):
            return copied
        case .denied:
            return ""
        case .failed:
            return pasteboardPlainText()
        }
    }

    private enum CopyResult {
        case copied(String)
        case denied
        case failed
    }

    private static func axFocusedSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let focusStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusStatus == .success,
              let focusedObject = focused,
              CFGetTypeID(focusedObject) == AXUIElementGetTypeID()
        else { return nil }
        var selected: AnyObject?
        let focusedElement = focusedObject as! AXUIElement
        let textStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selected
        )
        guard textStatus == .success else { return nil }
        let text = (selected as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func copySelectedText() -> CopyResult {
        waitUntilModifiersReleased()

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let previousChangeCount = pasteboard.changeCount

        postHIDCommandC()
        if waitForPasteboardChange(from: previousChangeCount, timeout: 0.35) {
            return finishCopy(pasteboard: pasteboard, snapshot: snapshot)
        }

        let scriptError = sendSystemEventsCopy(script: "tell application \"System Events\" to keystroke \"c\" using {command down}")
        if let scriptError,
           scriptError.contains("1002") || scriptError.contains("不允许发送按键") {
            snapshot.restore(onto: pasteboard)
            return .denied
        }
        if waitForPasteboardChange(from: previousChangeCount, timeout: 0.35) {
            return finishCopy(pasteboard: pasteboard, snapshot: snapshot)
        }

        snapshot.restore(onto: pasteboard)
        return .failed
    }

    private static func finishCopy(
        pasteboard: NSPasteboard,
        snapshot: PasteboardSnapshot
    ) -> CopyResult {
        let copied = pasteboardPlainText()
        snapshot.restore(onto: pasteboard)
        let trimmed = copied.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .failed : .copied(trimmed)
    }

    private static func postHIDCommandC() {
        let source = CGEventSource(stateID: .hidSystemState)
        let commandKey: CGKeyCode = 0x37
        let keyC: CGKeyCode = 8
        let tap = CGEventTapLocation.cghidEventTap

        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true)
        commandDown?.flags = .maskCommand
        commandDown?.post(tap: tap)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: tap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: tap)

        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false)
        commandUp?.flags = []
        commandUp?.post(tap: tap)
    }

    private static func sendSystemEventsCopy(script: String) -> String? {
        guard let appleScript = NSAppleScript(source: script) else {
            return "nilScript"
        }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        guard let error else { return nil }
        let number = error[NSAppleScript.errorNumber] ?? "?"
        let message = error[NSAppleScript.errorMessage] ?? ""
        return "\(number) \(message)"
    }

    private static func waitForPasteboardChange(from previous: Int, timeout: TimeInterval) -> Bool {
        let pasteboard = NSPasteboard.general
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != previous {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return pasteboard.changeCount != previous
    }

    private static func waitUntilModifiersReleased() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let deadline = Date().addingTimeInterval(0.35)
        while Date() < deadline {
            if NSEvent.modifierFlags.intersection(flags).isEmpty {
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private static func pasteboardPlainText() -> String {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return text
        }
        if let text = pasteboard.readObjects(forClasses: [NSString.self], options: nil)?.first as? String {
            return text
        }
        return ""
    }

}

private struct PasteboardSnapshot {
    private let items: [NSPasteboardItem]

    init(_ pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.compactMap { item in
            let copy = NSPasteboardItem()
            var wrote = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                    wrote = true
                }
            }
            return wrote ? copy : nil
        } ?? []
    }

    func restore(onto pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
