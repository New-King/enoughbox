import Foundation

/// Where a `.plugin` binary comes from. Runtime always copies into Application Support.
protocol PluginBinarySource: Sendable {
    /// Returns a local bundle URL ready to copy, or `nil` to try the next source.
    func resolveBundleURL(forPluginID pluginID: String) async throws -> URL?
}

/// Debug: sibling of EnoughBox.app in `BUILT_PRODUCTS_DIR` (`<id>.plugin`).
struct LocalBuildPluginSource: PluginBinarySource {
    func resolveBundleURL(forPluginID pluginID: String) async throws -> URL? {
        #if DEBUG
        let sibling = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(pluginID).plugin", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sibling.path) else {
            return nil
        }
        return sibling
        #else
        return nil
        #endif
    }
}

/// Release: download zip from manifest. Not wired yet — no CI artifact.
struct RemoteDownloadPluginSource: PluginBinarySource {
    func resolveBundleURL(forPluginID pluginID: String) async throws -> URL? {
        #if DEBUG
        return nil
        #else
        throw PluginInstallError.remoteSourceUnavailable(pluginID)
        #endif
    }
}
