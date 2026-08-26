import AppKit
import SwiftUI

@MainActor
final class TranslateTool {
    static let id = "com.enoughbox.translate"

    private let toastHandler: (String) -> Void
    private var panelController: TranslationPanelController?
    private var captureTask: Task<Void, Never>?

    init(toastHandler: @escaping (String) -> Void) {
        self.toastHandler = toastHandler
    }

    func activate() {
        HotkeyCenter.shared.register(HotkeyCatalog.translateSelectionID) { [weak self] in
            self?.translateSelection()
        }
    }

    func deactivate() {
        HotkeyCenter.shared.unregister(HotkeyCatalog.translateSelectionID)
        captureTask?.cancel()
        captureTask = nil
        panelController?.close()
        panelController = nil
    }

    func makeSettingsViewController() -> NSViewController {
        NSHostingController(rootView: TranslateSettingsView())
    }

    private func translateSelection() {
        captureTask?.cancel()
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let text = await SelectionCapture.textForTranslation()
            guard !Task.isCancelled else { return }
            if text.isEmpty {
                toastHandler(TranslateL10n.string("plugin.translate.toast.noSelection"))
            }
            presentPanel(sourceText: text)
        }
    }

    private func presentPanel(sourceText: String) {
        if panelController == nil {
            panelController = TranslationPanelController()
        }
        panelController?.present(sourceText: sourceText)
    }
}

enum TranslateL10n {
    static let bundle = Bundle.main
    static let tableName = "TranslateLocalizable"

    static func string(_ key: String) -> String {
        NSLocalizedString(key, tableName: tableName, bundle: bundle, comment: "")
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

    @State private var targetLanguage = TranslateSettings.targetLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            translationSection
            accessibilitySection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("plugin.translate.settings.section", tableName: TranslateL10n.tableName, bundle: TranslateL10n.bundle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(sectionHeaderColor)
                .textCase(.uppercase)

            HStack {
                Text("plugin.translate.settings.target", tableName: TranslateL10n.tableName, bundle: TranslateL10n.bundle)
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
                Text("plugin.translate.settings.engine", tableName: TranslateL10n.tableName, bundle: TranslateL10n.bundle)
                    .font(.system(size: 13))
                    .foregroundStyle(bodyColor)
                Spacer(minLength: 8)
                Text("plugin.translate.engine.mock", tableName: TranslateL10n.tableName, bundle: TranslateL10n.bundle)
                    .font(.system(size: 13))
                    .foregroundStyle(mutedColor)
            }

            Text("plugin.translate.settings.footer", tableName: TranslateL10n.tableName, bundle: TranslateL10n.bundle)
                .font(.system(size: 11))
                .foregroundStyle(mutedColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        )
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("plugin.translate.settings.accessibility", tableName: TranslateL10n.tableName, bundle: TranslateL10n.bundle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(sectionHeaderColor)
                .textCase(.uppercase)

            Text("plugin.translate.settings.accessibilityHint", tableName: TranslateL10n.tableName, bundle: TranslateL10n.bundle)
                .font(.system(size: 11))
                .foregroundStyle(mutedColor)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(action: openAccessibilitySettings) {
                    Text("plugin.translate.settings.openAccessibility", tableName: TranslateL10n.tableName, bundle: TranslateL10n.bundle)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(bodyColor)
                        .background(bodyColor.opacity(colorScheme == .dark ? 0.14 : 0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
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

    private var mutedColor: Color {
        colorScheme == .dark
            ? Color(red: 176 / 255, green: 176 / 255, blue: 179 / 255)
            : Color(red: 110 / 255, green: 110 / 255, blue: 115 / 255)
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 48 / 255, green: 48 / 255, blue: 50 / 255)
            : Color.white
    }

    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private func openAccessibilitySettings() {
        SelectionCapture.requestAccessibilityTrust()
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
