import Foundation
import EnoughBoxPluginSDK

struct PluginRegistrySnapshot: Codable {
    var plugins: [InstalledPluginRecord]
}

struct InstalledPluginRecord: Codable, Equatable {
    let id: String
    let iconName: String
    let version: String
    let capabilities: [PluginCapability]

    init(from plugin: InstalledPlugin) {
        id = plugin.id
        iconName = plugin.iconName
        version = plugin.version
        capabilities = plugin.capabilities
    }

    func toInstalledPlugin() -> InstalledPlugin {
        InstalledPlugin(id: id, iconName: iconName, version: version, capabilities: capabilities)
    }
}

final class PluginRegistry {
    static let shared = PluginRegistry()

    func load() -> [InstalledPlugin] {
        guard let data = try? Data(contentsOf: AppPaths.registryFile) else { return [] }
        guard let snapshot = try? JSONDecoder().decode(PluginRegistrySnapshot.self, from: data) else { return [] }
        return snapshot.plugins.map { $0.toInstalledPlugin() }
    }

    func save(_ plugins: [InstalledPlugin]) throws {
        try AppPaths.ensureDirectories()
        let snapshot = PluginRegistrySnapshot(plugins: plugins.map(InstalledPluginRecord.init))
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: AppPaths.registryFile, options: .atomic)
    }
}
