import AppKit
import EnoughBoxPluginSDK
import SwiftUI

@objc(SamplePluginPlugin)
public final class SamplePluginPlugin: NSObject, EnoughBoxPlugin {
    private weak var host: HostServices?

    public var id: String { "com.enoughbox.sample" }
    public var iconName: String { "puzzlepiece.extension" }
    public var version: String { "0.1.0" }

    public func localizedName(for locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier ?? "en"
        return language.hasPrefix("zh") ? "示例" : "Sample"
    }

    public func activate(host: HostServices) {
        self.host = host
        guard let hotkeys = host as? HostServicesHotkeys else { return }

        hotkeys.registerHotkey(HotkeyCatalog.sampleTriggerID) { [weak self] in
            self?.triggerDemoToast()
        }
    }

    public func deactivate() {
        (host as? HostServicesHotkeys)?.unregisterHotkey(HotkeyCatalog.sampleTriggerID)
        host = nil
    }

    public func makeSettingsViewController(host: HostServices) -> NSViewController {
        self.host = host
        return NSHostingController(rootView: SampleDemoSettingsView(onDemo: { [weak self] in
            self?.triggerDemoToast()
        }))
    }

    private func triggerDemoToast() {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let message = language.hasPrefix("zh") ? "示例插件已触发" : "Sample plugin triggered"
        host?.showToast(message)
    }
}

/// Hotkey UI lives in the host; plugin settings only expose plugin-specific actions.
private struct SampleDemoSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme

    let onDemo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("plugin.sample.section.demo")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(sectionHeaderColor)
                .textCase(.uppercase)

            Button(action: onDemo) {
                Text("plugin.sample.demoAction")
                    .foregroundStyle(bodyColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        )
    }

    private var sectionHeaderColor: Color {
        colorScheme == .dark
            ? Color(red: 176 / 255, green: 176 / 255, blue: 179 / 255)
            : Color(red: 110 / 255, green: 110 / 255, blue: 115 / 255)
    }

    private var bodyColor: Color {
        colorScheme == .dark
            ? Color(red: 224 / 255, green: 224 / 255, blue: 224 / 255)
            : Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255)
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 48 / 255, green: 48 / 255, blue: 50 / 255)
            : Color.white
    }

    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
}
