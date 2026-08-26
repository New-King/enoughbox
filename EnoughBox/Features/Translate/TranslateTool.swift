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

struct TranslateSettingsView: View {
    @Environment(\.designTokens) private var tokens
    @FocusState private var focusedField: String?

    @State private var targetLanguage = TranslateSettings.targetLanguage
    @State private var engine = TranslateSettings.engine
    @State private var youdaoAppID = TranslateSettings.youdaoAppID
    @State private var youdaoAppSecret = TranslateSettings.youdaoAppSecret
    @State private var youdaoAPIKey = TranslateSettings.youdaoAPIKey
    @State private var deepSeekAPIKey = TranslateSettings.deepSeekAPIKey
    @State private var deepSeekModel = TranslateSettings.deepSeekModel
    @State private var deepSeekBaseURL = TranslateSettings.deepSeekBaseURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            translationSection
            credentialsSection
            accessibilitySection
        }
        .defaultFocus($focusedField, nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .environment(\.openURL, OpenURLAction { _ in .discarded })
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsHeader("plugin.translate.settings.section")

            settingsRow("plugin.translate.settings.target") {
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

            settingsRow("plugin.translate.settings.engine") {
                Picker("", selection: $engine) {
                    ForEach(TranslationEngine.allCases) { item in
                        Text(item.localizedName).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: engine) { _, newValue in
                    TranslateSettings.engine = newValue
                }
            }

            hintText(engineFooterKey)
        }
        .settingsCard(tokens: tokens, resignFocus: resignFocus)
    }

    @ViewBuilder
    private var credentialsSection: some View {
        switch engine {
        case .youdao:
            VStack(alignment: .leading, spacing: 12) {
                settingsHeader("plugin.translate.settings.credentials")
                labeledField("plugin.translate.settings.appID", field: "youdao.appID", text: $youdaoAppID) {
                    TranslateSettings.youdaoAppID = youdaoAppID
                }
                labeledField("plugin.translate.settings.appSecret", field: "youdao.appSecret", text: $youdaoAppSecret) {
                    TranslateSettings.youdaoAppSecret = youdaoAppSecret
                }
                labeledField("plugin.translate.settings.apiKey", field: "youdao.apiKey", text: $youdaoAPIKey) {
                    TranslateSettings.youdaoAPIKey = youdaoAPIKey
                }
                hintText("plugin.translate.settings.youdaoHint")
            }
            .settingsCard(tokens: tokens, resignFocus: resignFocus)
        case .deepseek:
            VStack(alignment: .leading, spacing: 12) {
                settingsHeader("plugin.translate.settings.credentials")
                labeledField("plugin.translate.settings.apiKey", field: "deepseek.apiKey", text: $deepSeekAPIKey) {
                    TranslateSettings.deepSeekAPIKey = deepSeekAPIKey
                }
                labeledField("plugin.translate.settings.model", field: "deepseek.model", text: $deepSeekModel) {
                    TranslateSettings.deepSeekModel = deepSeekModel
                }
                labeledField("plugin.translate.settings.baseURL", field: "deepseek.baseURL", text: $deepSeekBaseURL) {
                    TranslateSettings.deepSeekBaseURL = deepSeekBaseURL
                }
                hintText("plugin.translate.settings.deepseekHint")
            }
            .settingsCard(tokens: tokens, resignFocus: resignFocus)
        case .system:
            EmptyView()
        }
    }

    private var engineFooterKey: String {
        switch engine {
        case .system:
            return "plugin.translate.settings.systemHint"
        case .youdao, .deepseek:
            return "plugin.translate.settings.footer"
        }
    }

    private func resignFocus() {
        focusedField = nil
    }

    private func hintText(_ key: String) -> some View {
        Text(verbatim: TranslateL10n.string(key))
            .font(.system(size: 11))
            .foregroundStyle(tokens.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .onTapGesture(perform: resignFocus)
    }

    private func settingsHeader(_ key: LocalizedStringKey) -> some View {
        Text(key, tableName: TranslateL10n.tableName, bundle: TranslateL10n.bundle)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tokens.inkMuted)
            .textCase(.uppercase)
            .onTapGesture(perform: resignFocus)
    }

    private func settingsRow<Content: View>(_ key: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(key, tableName: TranslateL10n.tableName, bundle: TranslateL10n.bundle)
                .font(.system(size: 13))
                .foregroundStyle(tokens.ink)
                .onTapGesture(perform: resignFocus)
            Spacer(minLength: 8)
            content()
        }
    }

    private func labeledField(
        _ key: LocalizedStringKey,
        field: String,
        text: Binding<String>,
        save: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key, tableName: TranslateL10n.tableName, bundle: TranslateL10n.bundle)
                .font(.system(size: 12))
                .foregroundStyle(tokens.inkSoft)
                .onTapGesture(perform: resignFocus)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: field)
                .onChange(of: text.wrappedValue) { _, _ in
                    save()
                }
        }
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsHeader("plugin.translate.settings.accessibility")

            Text("plugin.translate.settings.accessibilityHint", tableName: TranslateL10n.tableName, bundle: TranslateL10n.bundle)
                .font(.system(size: 11))
                .foregroundStyle(tokens.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture(perform: resignFocus)

            HStack {
                Spacer()
                Button(action: openAccessibilitySettings) {
                    Text("plugin.translate.settings.openAccessibility", tableName: TranslateL10n.tableName, bundle: TranslateL10n.bundle)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(tokens.ink)
                        .background(tokens.ink.opacity(0.1), in: Capsule())
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
        .settingsCard(tokens: tokens, resignFocus: resignFocus)
    }

    private func openAccessibilitySettings() {
        SelectionCapture.requestAccessibilityTrust()
    }
}

private extension View {
    func settingsCard(tokens: DesignTokens, resignFocus: @escaping () -> Void) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tokens.card)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onTapGesture(perform: resignFocus)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tokens.border, lineWidth: 1)
            )
    }
}
