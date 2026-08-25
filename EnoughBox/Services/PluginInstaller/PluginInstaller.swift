import Foundation

enum PluginInstallError: LocalizedError {
    case invalidDownloadURL
    case checksumMismatch
    case unpackFailed

    var errorDescription: String? {
        switch self {
        case .invalidDownloadURL: return "Invalid download URL"
        case .checksumMismatch: return "Checksum mismatch"
        case .unpackFailed: return "Failed to unpack plugin"
        }
    }
}

/// Downloads and installs plugins. Phase 2 uses simulated progress until manifest CDN is wired.
@MainActor
final class PluginInstaller {
    typealias ProgressHandler = (PluginInstallPhase) -> Void

    func install(_ plugin: StorePlugin, onPhase: @escaping ProgressHandler) async throws {
        onPhase(.downloading(progress: 0))

        // Phase 2a: simulated download. Replace with URLSession + manifest SHA256.
        let steps = 20
        for step in 1...steps {
            try await Task.sleep(for: .milliseconds(60))
            onPhase(.downloading(progress: Double(step) / Double(steps)))
        }

        onPhase(.installing)
        try await Task.sleep(for: .milliseconds(400))

        try AppPaths.ensureDirectories()
        let marker = AppPaths.pluginsDirectory
            .appendingPathComponent("\(plugin.id).installed", isDirectory: false)
        try Data(plugin.version.utf8).write(to: marker, options: .atomic)
    }

    func uninstall(_ plugin: InstalledPlugin) async throws {
        try await Task.sleep(for: .milliseconds(250))
        let marker = AppPaths.pluginsDirectory
            .appendingPathComponent("\(plugin.id).installed", isDirectory: false)
        try? FileManager.default.removeItem(at: marker)
    }
}
