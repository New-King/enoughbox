import Foundation
import SwiftUI
import EnoughBoxPluginSDK

struct InstalledPlugin: Identifiable, Equatable, Hashable {
    let id: String
    let iconName: String
    let version: String
    let capabilities: [PluginCapability]

    var localizedNameKey: LocalizedStringKey {
        switch id {
        case "com.enoughbox.sample": "plugin.sample.name"
        case "com.enoughbox.translate": "plugin.translate.name"
        default: LocalizedStringKey(id)
        }
    }
}

struct StorePlugin: Identifiable, Equatable {
    let id: String
    let iconName: String
    let version: String
    let capabilities: [PluginCapability]
    let nameKey: LocalizedStringKey
    let descriptionKey: LocalizedStringKey
    let comingSoon: Bool

    static func == (lhs: StorePlugin, rhs: StorePlugin) -> Bool {
        lhs.id == rhs.id
    }

    static let catalog: [StorePlugin] = [
        StorePlugin(
            id: "com.enoughbox.sample",
            iconName: "puzzlepiece.extension",
            version: "0.1.0",
            capabilities: [.hotkey, .clipboard],
            nameKey: "plugin.sample.name",
            descriptionKey: "plugin.sample.description",
            comingSoon: false
        ),
        StorePlugin(
            id: "com.enoughbox.translate",
            iconName: "character.book.closed",
            version: "0.1.0",
            capabilities: [.hotkey, .accessibility, .clipboard],
            nameKey: "plugin.translate.name",
            descriptionKey: "plugin.translate.description",
            comingSoon: false
        ),
        StorePlugin(
            id: "com.enoughbox.screenshot",
            iconName: "camera.viewfinder",
            version: "0.0.0",
            capabilities: [.screenRecording, .clipboard],
            nameKey: "plugin.comingSoon.screenshot.name",
            descriptionKey: "plugin.comingSoon.screenshot.description",
            comingSoon: true
        ),
    ]
}
