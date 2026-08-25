import Foundation

/// Swift-only host APIs for reading the current text selection in the frontmost app.
public protocol HostServicesSelection: HostServices {
    func isAccessibilityTrusted() -> Bool
    /// Opens nothing by itself; plugins should send the user to System Settings instead of the TCC prompt.
    func requestAccessibilityTrust()
    /// Best-effort selected text in the frontmost app. Empty if nothing is selected or access failed.
    func currentSelectedText() -> String
    /// Selected text if present; clipboard text only when no selection is detected.
    func textForTranslation() -> String
}
