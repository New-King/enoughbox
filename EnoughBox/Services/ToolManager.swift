import AppKit
import Foundation

@MainActor
final class ToolManager: ObservableObject {
    private let translateTool: TranslateTool
    private var activeToolIDs: Set<String> = []
    private var settingsControllers: [String: NSViewController] = [:]

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
        settingsControllers.removeValue(forKey: toolID)
    }

    func settingsViewController(for toolID: String) -> NSViewController? {
        guard toolID == TranslateTool.id else { return nil }
        if let controller = settingsControllers[toolID] {
            return controller
        }
        let controller = translateTool.makeSettingsViewController()
        settingsControllers[toolID] = controller
        return controller
    }
}
