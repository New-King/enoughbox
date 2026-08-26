import Foundation
import SwiftUI

enum ToolCapability: String, Codable, Sendable {
    case hotkey
    case accessibility
    case clipboard
}

struct EnabledTool: Identifiable, Equatable, Hashable {
    let id: String
    let iconName: String
    let version: String
    let capabilities: [ToolCapability]

    var localizedNameKey: LocalizedStringKey {
        switch id {
        case "com.enoughbox.sample": "plugin.sample.name"
        case "com.enoughbox.translate": "plugin.translate.name"
        case "com.enoughbox.screenshot": "plugin.screenshot.name"
        default: LocalizedStringKey(id)
        }
    }
}

struct BuiltInTool: Identifiable, Equatable {
    let id: String
    let iconName: String
    let version: String
    let capabilities: [ToolCapability]
    let nameKey: LocalizedStringKey
    let descriptionKey: LocalizedStringKey

    static func == (lhs: BuiltInTool, rhs: BuiltInTool) -> Bool {
        lhs.id == rhs.id
    }

    static var catalog: [BuiltInTool] {
        let tools = [
            BuiltInTool(
                id: "com.enoughbox.translate",
                iconName: "character.book.closed",
                version: "0.1.0",
                capabilities: [.hotkey, .accessibility],
                nameKey: "plugin.translate.name",
                descriptionKey: "plugin.translate.description"
            ),
            BuiltInTool(
                id: "com.enoughbox.screenshot",
                iconName: "camera.viewfinder",
                version: "0.1.0",
                capabilities: [.hotkey],
                nameKey: "plugin.screenshot.name",
                descriptionKey: "plugin.screenshot.description"
            ),
        ]
        return tools
    }
}
