import Foundation

/// Host-facing plugin contract. `@objc` + bundle loading in Phase 2.
@objc public protocol EnoughBoxPlugin: AnyObject {
    var id: String { get }
    var iconName: String { get }
    var version: String { get }

    func localizedName(for locale: Locale) -> String
    func activate(host: HostServices)
    func deactivate()
}

/// System capabilities exposed by the host (stubs for Phase 1 UI).
@objc public protocol HostServices: AnyObject {}

public enum PluginCapability: String, Codable, Sendable {
    case hotkey
    case accessibility
    case screenRecording
    case network
    case filesUserSelected
    case clipboard
}
