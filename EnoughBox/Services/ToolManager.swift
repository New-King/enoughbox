import Foundation

@MainActor
final class ToolManager: ObservableObject {
    private let translateTool: TranslateTool
    private let screenshotTool: ScreenshotTool
    private let clipboardTool: ClipboardTool
    private var activeToolIDs: Set<String> = []

    init(toastHandler: @escaping (String) -> Void) {
        translateTool = TranslateTool(toastHandler: toastHandler)
        screenshotTool = ScreenshotTool(toastHandler: toastHandler)
        clipboardTool = ClipboardTool()
    }

    func loadEnabled(_ tools: [EnabledTool]) {
        for tool in tools {
            load(toolID: tool.id)
        }
    }

    func load(toolID: String) {
        guard activeToolIDs.insert(toolID).inserted else { return }
        switch toolID {
        case TranslateTool.id:
            translateTool.activate()
        case ScreenshotTool.id:
            screenshotTool.activate()
        case ClipboardTool.id:
            clipboardTool.activate()
        default:
            activeToolIDs.remove(toolID)
        }
    }

    func unload(toolID: String) {
        guard activeToolIDs.remove(toolID) != nil else { return }
        switch toolID {
        case TranslateTool.id:
            translateTool.deactivate()
        case ScreenshotTool.id:
            screenshotTool.deactivate()
        case ClipboardTool.id:
            clipboardTool.deactivate()
        default:
            break
        }
    }
}
