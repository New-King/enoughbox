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
}

struct BuiltInTool: Identifiable, Equatable {
    let id: String
    let iconName: String
    let version: String
    let capabilities: [ToolCapability]
    let name: String
    let description: String

    static func == (lhs: BuiltInTool, rhs: BuiltInTool) -> Bool {
        lhs.id == rhs.id
    }

    static var catalog: [BuiltInTool] {
        [
            BuiltInTool(
                id: "com.enoughbox.translate",
                iconName: "bubble.left",
                version: "0.1.0",
                capabilities: [.hotkey, .accessibility],
                name: UIStrings.Tool.translateName,
                description: UIStrings.Tool.translateDescription
            ),
            BuiltInTool(
                id: "com.enoughbox.screenshot",
                iconName: "viewfinder",
                version: "0.1.0",
                capabilities: [.hotkey],
                name: UIStrings.Tool.screenshotName,
                description: UIStrings.Tool.screenshotDescription
            ),
            BuiltInTool(
                id: "com.enoughbox.clipboard",
                iconName: "clipboard",
                version: "0.1.0",
                capabilities: [.hotkey, .clipboard],
                name: UIStrings.Tool.clipboardName,
                description: UIStrings.Tool.clipboardDescription
            ),
        ]
    }
}
