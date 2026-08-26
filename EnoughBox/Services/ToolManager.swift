import Foundation

@MainActor
final class ToolManager: ObservableObject {
    private let translateTool: TranslateTool
    private var activeToolIDs: Set<String> = []

    init(toastHandler: @escaping (String) -> Void) {
        translateTool = TranslateTool(toastHandler: toastHandler)
    }

    func loadEnabled(_ tools: [EnabledTool]) {
        for tool in tools {
            load(toolID: tool.id)
        }
    }

    func load(toolID: String) {
        guard toolID == TranslateTool.id else { return }
        guard activeToolIDs.insert(toolID).inserted else { return }
        translateTool.activate()
    }

    func unload(toolID: String) {
        guard toolID == TranslateTool.id else { return }
        guard activeToolIDs.remove(toolID) != nil else { return }
        translateTool.deactivate()
    }
}
