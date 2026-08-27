import Foundation
import SwiftUI

enum ToastStyle {
    case standard
    case error
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var enabledTools: [EnabledTool] = []
    @Published var selectedToolID: String?
    @Published var isToolCenterPresented = false
    @Published var toastMessage: String?
    @Published private(set) var toastStyle: ToastStyle = .standard
    private var toastGeneration = 0

    private(set) lazy var toolManager = ToolManager { [weak self] message in
        self?.showToast(message)
    }

    private let registry = ToolRegistry.shared
    var hasEnabledTools: Bool { !enabledTools.isEmpty }

    var selectedTool: EnabledTool? {
        guard let selectedToolID else { return nil }
        return enabledTools.first { $0.id == selectedToolID }
    }

    init() {
        enabledTools = registry.load()
        selectedToolID = enabledTools.first?.id
        toolManager.loadEnabled(enabledTools)
    }

    func openToolCenter() {
        isToolCenterPresented = true
    }

    func enable(_ tool: BuiltInTool) {
        guard !enabledTools.contains(where: { $0.id == tool.id }) else { return }
        performEnable(tool)
    }

    func remove(_ tool: EnabledTool) {
        performRemove(tool)
    }

    func isEnabled(_ tool: BuiltInTool) -> Bool {
        enabledTools.contains { $0.id == tool.id }
    }

    func displayName(for tool: EnabledTool) -> String {
        switch tool.id {
        case "com.enoughbox.translate":
            return UIStrings.Tool.translateName
        case "com.enoughbox.screenshot":
            return UIStrings.Tool.screenshotName
        default:
            return tool.id
        }
    }

    func showToast(_ message: String, style: ToastStyle = .standard) {
        // Defer so AppKit hotkey / recorder callbacks never publish during SwiftUI body updates.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.toastStyle = style
            self.toastMessage = message
            self.toastGeneration += 1
            let generation = self.toastGeneration
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if self.toastGeneration == generation {
                    self.toastMessage = nil
                }
            }
        }
    }

    private func performEnable(_ tool: BuiltInTool) {
        let previousTools = enabledTools
        do {
            let enabledTool = EnabledTool(
                id: tool.id,
                iconName: tool.iconName,
                version: tool.version,
                capabilities: tool.capabilities
            )
            enabledTools.append(enabledTool)
            selectedToolID = enabledTool.id
            try registry.save(enabledTools)
            toolManager.load(toolID: enabledTool.id)
        } catch {
            enabledTools = previousTools
            selectedToolID = previousTools.first?.id
        }
    }

    private func performRemove(_ tool: EnabledTool) {
        let previousTools = enabledTools
        do {
            enabledTools.removeAll { $0.id == tool.id }
            if selectedToolID == tool.id {
                selectedToolID = enabledTools.first?.id
            }
            try registry.save(enabledTools)
            toolManager.unload(toolID: tool.id)
            HotkeyCenter.shared.clearShortcut(forToolID: tool.id)
        } catch {
            enabledTools = previousTools
            selectedToolID = previousTools.first?.id
        }
    }

    #if DEBUG
    static var previewPopulated: AppState {
        let state = AppState()
        if state.enabledTools.isEmpty {
            state.enabledTools = [
                EnabledTool(
                    id: "com.enoughbox.translate",
                    iconName: "character.book.closed",
                    version: "0.1.0",
                    capabilities: [.hotkey, .accessibility]
                ),
            ]
            state.selectedToolID = state.enabledTools.first?.id
        }
        return state
    }
    #endif
}
