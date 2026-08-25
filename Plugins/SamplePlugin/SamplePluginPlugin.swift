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
    let onDemo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("plugin.sample.section.demo")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Button(action: onDemo) {
                Text("plugin.sample.demoAction")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
