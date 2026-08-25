import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

/// Reusable host-owned recorder. KeyboardShortcuts remains responsible for
/// persistence and global registration; this view only owns recording UX.
struct ShortcutRecorderField: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    let onSaved: (KeyboardShortcuts.Shortcut) -> Void
    let onConflict: (ShortcutConflict) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(name: name)
        button.onSaved = onSaved
        button.onConflict = onConflict
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        nsView.shortcutName = name
        nsView.onSaved = onSaved
        nsView.onConflict = onConflict
        nsView.refreshTitle()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: ShortcutRecorderButton,
        context: Context
    ) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        return CGSize(width: proposal.width ?? intrinsic.width, height: intrinsic.height)
    }

    static func dismantleNSView(_ nsView: ShortcutRecorderButton, coordinator: ()) {
        nsView.stopRecording()
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcutName: KeyboardShortcuts.Name {
        didSet {
            guard shortcutName != oldValue else { return }
            refreshTitle()
        }
    }

    var onSaved: ((KeyboardShortcuts.Shortcut) -> Void)?
    var onConflict: ((ShortcutConflict) -> Void)?

    private var isRecording = false
    private var eventMonitor: Any?
    private var exitObservers: [NSObjectProtocol] = []
    private var previewTitle: String?
    private var didPreviewKeyForHeldModifiers = false

    private static let functionKeyCodes: Set<UInt16> = Set([
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
        kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
        kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ].map(UInt16.init))

    override var acceptsFirstResponder: Bool { true }

    init(name: KeyboardShortcuts.Name) {
        shortcutName = name
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 24))
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 13, weight: .medium)
        cell?.lineBreakMode = .byTruncatingTail
        target = self
        action = #selector(beginRecording)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopRecording()
    }

    @objc private func beginRecording() {
        guard !isRecording else { return }
        guard window?.makeFirstResponder(self) == true else { return }

        isRecording = true
        previewTitle = nil
        didPreviewKeyForHeldModifiers = false
        HotkeyCenter.shared.suspendForShortcutRecording()
        installEventMonitor()
        observeExits()
        refreshTitle()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        previewTitle = nil
        didPreviewKeyForHeldModifiers = false

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        exitObservers.forEach(NotificationCenter.default.removeObserver)
        exitObservers.removeAll()

        HotkeyCenter.shared.resumeAfterShortcutRecording()
        refreshTitle()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        handle(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handle(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        let modifiers = primaryModifiers(in: event)
        if modifiers.isEmpty {
            if !didPreviewKeyForHeldModifiers {
                previewTitle = nil
                refreshTitle()
            }
            didPreviewKeyForHeldModifiers = false
            return
        }

        guard !didPreviewKeyForHeldModifiers else { return }
        previewTitle = symbolicRepresentation(of: modifiers)
        refreshTitle()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopRecording()
        }
    }

    func refreshTitle() {
        if isRecording {
            title = previewTitle ?? String(localized: "plugin.shortcut.press")
        } else {
            title = KeyboardShortcuts.getShortcut(for: shortcutName)
                .map(String.init(describing:))
                ?? String(localized: "plugin.shortcut.set")
        }
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            guard let self, isRecording else { return event }

            if event.type == .leftMouseUp || event.type == .rightMouseUp {
                let point = convert(event.locationInWindow, from: nil)
                if !bounds.insetBy(dx: -3, dy: -3).contains(point) {
                    window?.makeFirstResponder(nil)
                    return event
                }
                return nil
            }

            if isPlainTab(event) {
                window?.makeFirstResponder(nil)
                return event
            }

            handle(event)
            return nil
        }
    }

    private func observeExits() {
        let center = NotificationCenter.default
        exitObservers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.window?.makeFirstResponder(nil)
        })
        if let window {
            exitObservers.append(center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.stopRecording()
            })
        }
    }

    private func handle(_ event: NSEvent) {
        if isPlainEscape(event) {
            window?.makeFirstResponder(nil)
            return
        }

        if isPlainDelete(event) {
            KeyboardShortcuts.setShortcut(nil, for: shortcutName)
            window?.makeFirstResponder(nil)
            return
        }

        guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
            return
        }

        previewTitle = String(describing: shortcut)
        didPreviewKeyForHeldModifiers = !primaryModifiers(in: event).isEmpty
        refreshTitle()

        guard isValidGlobalShortcut(event) else { return }
        if let conflict = ShortcutConflictDetector.conflict(
            for: shortcut,
            excluding: shortcutName
        ) {
            onConflict?(conflict)
            return
        }

        KeyboardShortcuts.setShortcut(shortcut, for: shortcutName)
        // setShortcut registers immediately. Disable again while this control
        // keeps recording, otherwise the new hotkey steals the next attempt.
        HotkeyCenter.shared.suspendForShortcutRecording()
        onSaved?(shortcut)
    }

    private func isValidGlobalShortcut(_ event: NSEvent) -> Bool {
        if Self.functionKeyCodes.contains(event.keyCode) {
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return !flags.intersection([.command, .control, .option]).isEmpty
    }

    private func isPlainEscape(_ event: NSEvent) -> Bool {
        event.keyCode == UInt16(kVK_Escape) && primaryModifiers(in: event).isEmpty
    }

    private func isPlainDelete(_ event: NSEvent) -> Bool {
        let deleteKeys = [UInt16(kVK_Delete), UInt16(kVK_ForwardDelete)]
        return deleteKeys.contains(event.keyCode) && primaryModifiers(in: event).isEmpty
    }

    private func isPlainTab(_ event: NSEvent) -> Bool {
        event.keyCode == UInt16(kVK_Tab) && primaryModifiers(in: event).isEmpty
    }

    private func primaryModifiers(in event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .control, .option, .shift])
    }

    private func symbolicRepresentation(of modifiers: NSEvent.ModifierFlags) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }
}

enum ShortcutConflict {
    case duplicate
    case system
    case menuItem(String)

    var localizedMessage: String {
        switch self {
        case .duplicate:
            String(localized: "plugin.shortcut.conflict.duplicate")
        case .system:
            String(localized: "plugin.shortcut.conflict.system")
        case let .menuItem(title):
            String(
                format: String(localized: "plugin.shortcut.conflict.menu.format"),
                title
            )
        }
    }
}

@MainActor
private enum ShortcutConflictDetector {
    static func conflict(
        for shortcut: KeyboardShortcuts.Shortcut,
        excluding name: KeyboardShortcuts.Name
    ) -> ShortcutConflict? {
        if HotkeyCenter.shared.hasShortcutConflict(shortcut, excluding: name) {
            return .duplicate
        }
        if let menuItem = matchingMenuItem(for: shortcut, in: NSApp.mainMenu) {
            return .menuItem(menuItem.title)
        }
        if systemShortcuts().contains(shortcut) {
            return .system
        }
        return nil
    }

    private static func matchingMenuItem(
        for shortcut: KeyboardShortcuts.Shortcut,
        in menu: NSMenu?
    ) -> NSMenuItem? {
        guard let menu else { return nil }

        for item in menu.items {
            var key = item.keyEquivalent
            var modifiers = item.keyEquivalentModifierMask
                .intersection(.deviceIndependentFlagsMask)

            if shortcut.modifiers.contains(.shift), key.lowercased() != key {
                key = key.lowercased()
                modifiers.insert(.shift)
            }

            let shortcutModifiers = shortcut.modifiers
                .intersection(.deviceIndependentFlagsMask)
            if shortcut.nsMenuItemKeyEquivalent == key,
               shortcutModifiers == modifiers {
                return item
            }
            if let match = matchingMenuItem(for: shortcut, in: item.submenu) {
                return match
            }
        }
        return nil
    }

    private static func systemShortcuts() -> Set<KeyboardShortcuts.Shortcut> {
        var shortcutsReference: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&shortcutsReference) == noErr,
              let shortcuts = shortcutsReference?.takeRetainedValue() as? [[String: Any]]
        else {
            return []
        }

        return Set(shortcuts.compactMap { value in
            guard (value[kHISymbolicHotKeyEnabled] as? Bool) == true,
                  let keyCode = value[kHISymbolicHotKeyCode] as? Int,
                  let modifiers = value[kHISymbolicHotKeyModifiers] as? Int
            else {
                return nil
            }
            return KeyboardShortcuts.Shortcut(
                carbonKeyCode: keyCode,
                carbonModifiers: modifiers
            )
        })
    }
}
