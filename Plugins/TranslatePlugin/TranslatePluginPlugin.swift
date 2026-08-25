import AppKit
import EnoughBoxPluginSDK
import SwiftUI

@objc(TranslatePluginPlugin)
public final class TranslatePluginPlugin: NSObject, EnoughBoxPlugin {
    private weak var host: HostServices?
    private var panelController: TranslationPanelController?

    public var id: String { "com.enoughbox.translate" }
    public var iconName: String { "character.book.closed" }
    public var version: String { "0.1.0" }

    public func localizedName(for locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier ?? "en"
        return language.hasPrefix("zh") ? "翻译" : "Translate"
    }

    public func activate(host: HostServices) {
        self.host = host
        guard let hotkeys = host as? HostServicesHotkeys else { return }

        hotkeys.registerHotkey(HotkeyCatalog.translateSelectionID) { [weak self] in
            Task { @MainActor in
                self?.translateSelection()
            }
        }
    }

    public func deactivate() {
        (host as? HostServicesHotkeys)?.unregisterHotkey(HotkeyCatalog.translateSelectionID)
        Task { @MainActor [weak self] in
            self?.panelController?.close()
            self?.panelController = nil
        }
        host = nil
    }

    public func makeSettingsViewController(host: HostServices) -> NSViewController {
        self.host = host
        return NSHostingController(rootView: TranslateSettingsView(host: host))
    }

    @MainActor
    private func translateSelection() {
        let selected = (host as? HostServicesSelection)?.currentSelectedText() ?? ""
        let text: String
        if selected.isEmpty {
            text = (host as? HostServicesClipboard)?.clipboardText() ?? ""
        } else {
            text = selected
        }

        if text.isEmpty {
            host?.showToast(TranslateL10n.string("plugin.translate.toast.noSelection"))
        }

        if panelController == nil {
            panelController = TranslationPanelController()
        }
        panelController?.present(sourceText: text)
    }
}

enum TranslateL10n {
    static let bundle = Bundle(for: TranslatePluginPlugin.self)

    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

enum TranslateLanguage: String, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case en

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .zhHans:
            return TranslateL10n.string("plugin.translate.language.zhHans")
        case .en:
            return TranslateL10n.string("plugin.translate.language.en")
        }
    }

    var speechLanguage: String {
        switch self {
        case .zhHans: return "zh-CN"
        case .en: return "en-US"
        }
    }
}

enum TranslateSettings {
    private static let targetKey = "com.enoughbox.translate.targetLanguage"

    static var targetLanguage: TranslateLanguage {
        get {
            TranslateLanguage(rawValue: UserDefaults.standard.string(forKey: targetKey) ?? "") ?? .zhHans
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: targetKey)
        }
    }
}

private struct TranslateSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    let host: HostServices

    @State private var targetLanguage = TranslateSettings.targetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("plugin.translate.settings.section", bundle: TranslateL10n.bundle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(sectionHeaderColor)
                .textCase(.uppercase)

            HStack {
                Text("plugin.translate.settings.target", bundle: TranslateL10n.bundle)
                    .font(.system(size: 13))
                    .foregroundStyle(bodyColor)
                Spacer(minLength: 8)
                Picker("", selection: $targetLanguage) {
                    ForEach(TranslateLanguage.allCases) { language in
                        Text(language.localizedName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                .onChange(of: targetLanguage) { _, newValue in
                    TranslateSettings.targetLanguage = newValue
                }
            }

            HStack {
                Text("plugin.translate.settings.engine", bundle: TranslateL10n.bundle)
                    .font(.system(size: 13))
                    .foregroundStyle(bodyColor)
                Spacer(minLength: 8)
                Text("plugin.translate.engine.mock", bundle: TranslateL10n.bundle)
                    .font(.system(size: 13))
                    .foregroundStyle(mutedColor)
            }

            Text("plugin.translate.settings.footer", bundle: TranslateL10n.bundle)
                .font(.system(size: 11))
                .foregroundStyle(mutedColor)
                .fixedSize(horizontal: false, vertical: true)

            if let selection = host as? HostServicesSelection, !selection.isAccessibilityTrusted() {
                Button(action: openAccessibilitySettings) {
                    Text("plugin.translate.settings.openAccessibility", bundle: TranslateL10n.bundle)
                        .foregroundStyle(bodyColor)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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

    private var mutedColor: Color {
        colorScheme == .dark
            ? Color(red: 176 / 255, green: 176 / 255, blue: 179 / 255)
            : Color(red: 110 / 255, green: 110 / 255, blue: 115 / 255)
    }

    private func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
