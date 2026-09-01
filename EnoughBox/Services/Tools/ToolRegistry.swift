import Foundation

struct ToolRegistrySnapshot: Codable {
    var tools: [EnabledToolRecord]

    enum CodingKeys: String, CodingKey {
        case tools = "plugins"
    }
}

struct EnabledToolRecord: Codable, Equatable {
    let id: String
    let iconName: String
    let version: String
    let capabilities: [ToolCapability]

    init(from tool: EnabledTool) {
        id = tool.id
        iconName = tool.iconName
        version = tool.version
        capabilities = tool.capabilities
    }

    func toEnabledTool() -> EnabledTool {
        EnabledTool(id: id, iconName: iconName, version: version, capabilities: capabilities)
    }
}

final class ToolRegistry {
    static let shared = ToolRegistry()

    func load() -> [EnabledTool] {
        guard let data = try? Data(contentsOf: AppPaths.registryFile) else { return [] }
        guard let snapshot = try? JSONDecoder().decode(ToolRegistrySnapshot.self, from: data) else { return [] }
        return snapshot.tools.compactMap { record in
            guard let catalog = BuiltInTool.catalog.first(where: { $0.id == record.id }) else { return nil }
            return EnabledTool(
                id: record.id,
                iconName: catalog.iconName,
                version: record.version,
                capabilities: record.capabilities
            )
        }
    }

    func save(_ tools: [EnabledTool]) throws {
        try AppPaths.ensureDirectories()
        let snapshot = ToolRegistrySnapshot(tools: tools.map(EnabledToolRecord.init))
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: AppPaths.registryFile, options: .atomic)
    }
}
