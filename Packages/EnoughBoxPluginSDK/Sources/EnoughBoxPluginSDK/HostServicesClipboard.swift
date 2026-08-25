import Foundation

/// Swift-only clipboard access for plugins.
public protocol HostServicesClipboard: HostServices {
    /// Plain text currently on the general pasteboard, trimmed. Empty if none.
    func clipboardText() -> String
}
