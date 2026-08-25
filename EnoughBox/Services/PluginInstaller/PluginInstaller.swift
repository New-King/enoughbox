import Foundation

enum PluginInstallError: LocalizedError {
    case sourceMissing(String)
    case copyFailed(String)
    case remoteSourceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .sourceMissing(id):
            return "No installable plugin binary for \(id)"
        case let .copyFailed(reason):
            return "Failed to install plugin: \(reason)"
        case let .remoteSourceUnavailable(id):
            return "Remote plugin download is not available yet (\(id))"
        }
    }
}

/// Installs into Application Support only. Debug copies Xcode build products; Release will download.
@MainActor
final class PluginInstaller {
    typealias ProgressHandler = (PluginInstallPhase) -> Void

    private let sources: [any PluginBinarySource]

    init(sources: [any PluginBinarySource]? = nil) {
        self.sources = sources ?? [
            LocalBuildPluginSource(),
            RemoteDownloadPluginSource(),
        ]
    }

    func install(_ plugin: StorePlugin, onPhase: @escaping ProgressHandler) async throws {
        onPhase(.downloading(progress: 1))
        onPhase(.installing)

        let sourceURL = try await resolveSourceURL(forPluginID: plugin.id)
        try AppPaths.ensureDirectories()
        try copyPlugin(from: sourceURL, pluginID: plugin.id)
    }

    func uninstall(_ plugin: InstalledPlugin) async throws {
        let destination = PluginLoader.bundleURL(forPluginID: plugin.id)
        try? FileManager.default.removeItem(at: destination)
    }

    private func resolveSourceURL(forPluginID pluginID: String) async throws -> URL {
        var lastError: Error?
        for source in sources {
            do {
                if let url = try await source.resolveBundleURL(forPluginID: pluginID) {
                    return url
                }
            } catch {
                lastError = error
            }
        }
        throw lastError ?? PluginInstallError.sourceMissing(pluginID)
    }

    private func copyPlugin(from source: URL, pluginID: String) throws {
        let destination = PluginLoader.bundleURL(forPluginID: pluginID)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw PluginInstallError.copyFailed(error.localizedDescription)
        }
    }
}
