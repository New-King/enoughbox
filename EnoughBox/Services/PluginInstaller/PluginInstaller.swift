import Foundation

enum PluginInstallError: LocalizedError {
    case bundledPluginMissing(String)
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case let .bundledPluginMissing(id):
            return "Bundled plugin missing for \(id)"
        case let .copyFailed(reason):
            return "Failed to install plugin: \(reason)"
        }
    }
}

/// Installs plugins by copying embedded `.plugin` bundles into Application Support.
@MainActor
final class PluginInstaller {
    typealias ProgressHandler = (PluginInstallPhase) -> Void

    func install(_ plugin: StorePlugin, onPhase: @escaping ProgressHandler) async throws {
        onPhase(.downloading(progress: 0))

        let steps = 12
        for step in 1...steps {
            try await Task.sleep(for: .milliseconds(50))
            onPhase(.downloading(progress: Double(step) / Double(steps)))
        }

        onPhase(.installing)

        guard let source = PluginLoader.embeddedBundleURL(forPluginID: plugin.id) else {
            throw PluginInstallError.bundledPluginMissing(plugin.id)
        }

        try AppPaths.ensureDirectories()

        let destination = PluginLoader.bundleURL(forPluginID: plugin.id)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw PluginInstallError.copyFailed(error.localizedDescription)
        }

        try await Task.sleep(for: .milliseconds(150))
    }

    func uninstall(_ plugin: InstalledPlugin) async throws {
        try await Task.sleep(for: .milliseconds(200))

        let destination = PluginLoader.bundleURL(forPluginID: plugin.id)
        try? FileManager.default.removeItem(at: destination)
    }
}
