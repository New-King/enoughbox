import ApplicationServices
import AppKit
import Foundation

enum SelectionCapture {
    private(set) static var lastDebugLine = ""
    private(set) static var lastLogPath = ""

    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityTrust() {}

    static func clipboardText() -> String {
        pasteboardPlainText()
    }

    static func textForTranslation() -> String {
        let trace = Trace()
        trace.add("app=\(Bundle.main.bundleURL.path)")
        trace.add("frontmost=\(frontmostDescription())")
        trace.add("axTrusted=\(AXIsProcessTrusted())")

        if let ax = axFocusedSelectedText() {
            trace.add("ax=ok len=\(ax.count) preview=\(preview(ax))")
            finish(trace, source: "ax", text: ax)
            return ax
        }
        trace.add("ax=empty")

        if let copied = copySelectedText(trace: trace) {
            trace.add("copy=ok len=\(copied.count) preview=\(preview(copied))")
            finish(trace, source: "copy", text: copied)
            return copied
        }

        if trace.lines.contains(where: { $0.contains("1002") || $0.contains("不允许发送按键") }) {
            finish(trace, source: "denied", text: "")
            return ""
        }

        let clipboard = clipboardText()
        trace.add("clipboardFallback len=\(clipboard.count) preview=\(preview(clipboard))")
        finish(trace, source: "clipboard", text: clipboard)
        return clipboard
    }

    static func currentSelectedText() -> String {
        if let ax = axFocusedSelectedText(), !ax.isEmpty {
            return ax
        }
        return copySelectedText(trace: Trace()) ?? ""
    }

    private static func axFocusedSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let focusStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusStatus == .success else { return nil }
        var selected: AnyObject?
        let textStatus = AXUIElementCopyAttributeValue(
            focused as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selected
        )
        guard textStatus == .success else { return nil }
        let text = (selected as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func copySelectedText(trace: Trace) -> String? {
        waitUntilModifiersReleased()
        trace.add("modifiers=\(modifierDescription())")

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let previousChangeCount = pasteboard.changeCount
        trace.add("pasteboardCountBefore=\(previousChangeCount)")

        postHIDCommandC()
        trace.add("hidCopy=posted")
        if waitForPasteboardChange(from: previousChangeCount, timeout: 0.35) {
            return finishCopy(pasteboard: pasteboard, snapshot: snapshot, previousChangeCount: previousChangeCount, trace: trace)
        }

        let scriptError = sendSystemEventsCopy(script: "tell application \"System Events\" to keystroke \"c\" using {command down}")
        if let scriptError {
            trace.add("appleScriptKeystrokeError=\(scriptError)")
        } else {
            trace.add("appleScriptKeystroke=ok")
        }
        if waitForPasteboardChange(from: previousChangeCount, timeout: 0.35) {
            return finishCopy(pasteboard: pasteboard, snapshot: snapshot, previousChangeCount: previousChangeCount, trace: trace)
        }

        snapshot.restore(onto: pasteboard)
        trace.add("pasteboardCountAfter=\(pasteboard.changeCount)")
        trace.add("copy=failed changeCountUnchanged")
        return nil
    }

    private static func finishCopy(
        pasteboard: NSPasteboard,
        snapshot: PasteboardSnapshot,
        previousChangeCount: Int,
        trace: Trace
    ) -> String? {
        trace.add("pasteboardCountAfter=\(pasteboard.changeCount)")
        let copied = pasteboardPlainText()
        snapshot.restore(onto: pasteboard)
        let trimmed = copied.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trace.add("copy=failed emptyAfterChange")
            return nil
        }
        return trimmed
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

    private static func modifierDescription() -> String {
        var parts: [String] = []
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) { parts.append("cmd") }
        if flags.contains(.option) { parts.append("opt") }
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.shift) { parts.append("shift") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }

    private static func frontmostDescription() -> String {
        let app = NSWorkspace.shared.frontmostApplication
        let name = app?.localizedName ?? "?"
        let bundle = app?.bundleIdentifier ?? "?"
        return "\(name) (\(bundle))"
    }

    private static func preview(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")
        if collapsed.count <= 40 {
            return collapsed
        }
        return String(collapsed.prefix(40)) + "…"
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

    private static func finish(_ trace: Trace, source: String, text: String) {
        lastDebugLine = "source=\(source); " + trace.lines.joined(separator: "; ")
        lastLogPath = appendLog(lastDebugLine)
        NSLog("EnoughBox.selection %@", lastDebugLine)
    }

    private static func appendLog(_ line: String) -> String {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/EnoughBox", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("selection.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let record = "\(stamp) \(line)\n"
        if let data = record.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: file.path) {
                if let handle = try? FileHandle(forWritingTo: file) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: file)
            }
        }
        return file.path
    }
}

private final class Trace {
    var lines: [String] = []

    func add(_ line: String) {
        lines.append(line)
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
