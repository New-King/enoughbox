import Foundation
import EnoughBoxPluginSDK

enum AppPaths {
    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("EnoughBox", isDirectory: true)
    }

    static var pluginsDirectory: URL {
        applicationSupport.appendingPathComponent("Plugins", isDirectory: true)
    }

    static var registryFile: URL {
        applicationSupport.appendingPathComponent("registry.json")
    }

    static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
    }
}
