import AppKit
import KeyboardShortcuts

@MainActor
enum InputRecovery {
    static func recoverIfNeeded() {
        ScreenshotOverlayController.dismissOrphanedOverlayWindows()
        recoverStuckShortcutSuspend()
        recoverOrphanedPanelKeyWindow()
        if !KeyboardShortcuts.isEnabled {
            KeyboardShortcuts.isEnabled = true
        }
    }

    private static func recoverStuckShortcutSuspend() {
        guard HotkeyCenter.shared.isShortcutRecording else { return }
        let recorderIsActive = NSApp.windows.contains { window in
            guard let recorder = window.firstResponder as? ShortcutRecorderButton else { return false }
            return recorder.isRecordingShortcut
        }
        if !recorderIsActive {
            HotkeyCenter.shared.resumeAfterShortcutRecording()
        }
    }

    private static func recoverOrphanedPanelKeyWindow() {
        guard !ScreenshotOverlayController.isSessionOnScreen else { return }
        guard let keyWindow = NSApp.keyWindow as? NSPanel else { return }
        if !keyWindow.isVisible {
            HostWindowFocus.returnToMainWindow()
        }
    }
}
