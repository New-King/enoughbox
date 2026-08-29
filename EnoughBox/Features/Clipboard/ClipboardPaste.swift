import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Writes clipboard history back to the app that was frontmost before the panel opened.
enum ClipboardPaste {
    private static var targetApp: NSRunningApplication?
    private static var promptedForAccessibility = false

    static func rememberTarget() {
        let ownBundleID = Bundle.main.bundleIdentifier
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != ownBundleID,
              app.activationPolicy == .regular,
              !app.isTerminated
        else {
            targetApp = nil
            return
        }
        targetApp = app
    }

    enum Result {
        case pasted
        case copiedOnly
    }

    @discardableResult
    static func perform(releasing panel: NSWindow?, completion: (() -> Void)? = nil) -> Result {
        releasePanelFocus(panel)

        guard SelectionCapture.hasAccessibilityTrust() else {
            if !promptedForAccessibility {
                promptedForAccessibility = true
                SelectionCapture.requestAccessibilityTrust()
            }
            completion?()
            return .copiedOnly
        }

        guard let app = targetApp, !app.isTerminated else {
            completion?()
            return .copiedOnly
        }

        app.activate(options: [.activateIgnoringOtherApps])
        waitUntilTargetIsActive(app) {
            postPasteWhenModifiersReleased(attempt: 0, completion: completion)
        }
        return .pasted
    }

    private static func releasePanelFocus(_ panel: NSWindow?) {
        panel?.makeFirstResponder(nil)
        if panel?.isKeyWindow == true {
            panel?.resignKey()
        }
    }

    private static func waitUntilTargetIsActive(
        _ app: NSRunningApplication,
        attempt: Int = 0,
        completion: @escaping () -> Void
    ) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            completion()
            return
        }
        guard attempt < 25 else {
            completion()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            waitUntilTargetIsActive(app, attempt: attempt + 1, completion: completion)
        }
    }

    private static func postPasteWhenModifiersReleased(attempt: Int, completion: (() -> Void)?) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if attempt >= 40 {
            NSSound.beep()
            completion?()
            return
        }
        guard held.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
                postPasteWhenModifiersReleased(attempt: attempt + 1, completion: completion)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            guard !IsSecureEventInputEnabled() else {
                NSSound.beep()
                completion?()
                return
            }
            postCommandV()
            completion?()
        }
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_V),
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_V),
                  keyDown: false
              )
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
