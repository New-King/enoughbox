import AppKit
import Foundation

/// Host-facing plugin contract. Implement as `NSObject` subclass with `@objc(YourPluginClass)`.
@objc public protocol EnoughBoxPlugin: NSObjectProtocol {
    var id: String { get }
    var iconName: String { get }
    var version: String { get }

    func localizedName(for locale: Locale) -> String
    func activate(host: HostServices)
    func deactivate()
    func makeSettingsViewController(host: HostServices) -> NSViewController
}

/// Capabilities the host exposes to plugins at runtime.
@objc public protocol HostServices: NSObjectProtocol {
    @objc func showToast(_ message: String)
    @objc func requestAccessibilityTrust()
    @objc func isAccessibilityTrusted() -> Bool
    @objc func currentSelectedText() -> String
    @objc func textForTranslation() -> String
    @objc func clipboardText() -> String
}

public enum PluginCapability: String, Codable, Sendable {
    case hotkey
    case accessibility
    case screenRecording
    case network
    case filesUserSelected
    case clipboard
}
