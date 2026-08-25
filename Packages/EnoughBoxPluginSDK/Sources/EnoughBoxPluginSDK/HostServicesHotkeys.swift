import AppKit
import Foundation

/// Swift-only host APIs (plugins cast `HostServices` to this when needed).
public protocol HostServicesHotkeys: HostServices {
    func registerHotkey(_ identifier: String, handler: @escaping () -> Void)
    func unregisterHotkey(_ identifier: String)
}
