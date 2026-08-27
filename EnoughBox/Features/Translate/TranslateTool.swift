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

    private func beginTranslation() {
        captureTask?.cancel()
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let text = await SelectionCapture.textForTranslation()
            guard !Task.isCancelled else { return }
            if text.isEmpty {
                toastHandler(UIStrings.Translate.noSelection)
            }
            presentPanel(sourceText: text)
        }
    }

    private func translateSelection() {
        if SelectionCapture.hasAccessibilityTrust() {
            beginTranslation()
        } else {
            SelectionCapture.requestAccessibilityTrust()
        }
    }

    private func presentPanel(sourceText: String) {
        if panelController == nil {
            panelController = TranslationPanelController()
        }
        panelController?.present(sourceText: sourceText)
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
            settingsHeader(UIStrings.Translate.settingsSection)

            settingsRow(UIStrings.Translate.targetLanguage) {
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

            settingsRow(UIStrings.Translate.engine) {
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

            hintText(engineFooterText)
        }
        .settingsCard(tokens: tokens, resignFocus: resignFocus)
    }

    @ViewBuilder
    private var credentialsSection: some View {
        switch engine {
        case .youdao:
            VStack(alignment: .leading, spacing: 12) {
                settingsHeader(UIStrings.Translate.credentials)
                labeledField(UIStrings.Translate.appID, field: "youdao.appID", text: $youdaoAppID) {
                    TranslateSettings.youdaoAppID = youdaoAppID
                }
                labeledField(UIStrings.Translate.appSecret, field: "youdao.appSecret", text: $youdaoAppSecret) {
                    TranslateSettings.youdaoAppSecret = youdaoAppSecret
                }
                labeledField(UIStrings.Translate.apiKey, field: "youdao.apiKey", text: $youdaoAPIKey) {
                    TranslateSettings.youdaoAPIKey = youdaoAPIKey
                }
                hintText(UIStrings.Translate.youdaoHint)
            }
            .settingsCard(tokens: tokens, resignFocus: resignFocus)
        case .deepseek:
            VStack(alignment: .leading, spacing: 12) {
                settingsHeader(UIStrings.Translate.credentials)
                labeledField(UIStrings.Translate.apiKey, field: "deepseek.apiKey", text: $deepSeekAPIKey) {
                    TranslateSettings.deepSeekAPIKey = deepSeekAPIKey
                }
                labeledField(UIStrings.Translate.model, field: "deepseek.model", text: $deepSeekModel) {
                    TranslateSettings.deepSeekModel = deepSeekModel
                }
                labeledField(UIStrings.Translate.baseURL, field: "deepseek.baseURL", text: $deepSeekBaseURL) {
                    TranslateSettings.deepSeekBaseURL = deepSeekBaseURL
                }
                hintText(UIStrings.Translate.deepseekHint)
            }
            .settingsCard(tokens: tokens, resignFocus: resignFocus)
        case .system:
            EmptyView()
        }
    }

    private var engineFooterText: String {
        switch engine {
        case .system:
            UIStrings.Translate.systemHint
        case .youdao, .deepseek:
            UIStrings.Translate.footer
        }
    }

    private func resignFocus() {
        guard !HotkeyCenter.shared.isShortcutRecording else { return }
        focusedField = nil
    }

    private func hintText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(tokens.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .onTapGesture(perform: resignFocus)
    }

    private func settingsHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tokens.inkMuted)
            .textCase(.uppercase)
            .onTapGesture(perform: resignFocus)
    }

    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(tokens.ink)
                .onTapGesture(perform: resignFocus)
            Spacer(minLength: 8)
            content()
        }
    }

    private func labeledField(
        _ title: String,
        field: String,
        text: Binding<String>,
        save: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
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
            settingsHeader(UIStrings.Translate.accessibility)

            Text(UIStrings.Translate.accessibilityHint)
                .font(.system(size: 11))
                .foregroundStyle(tokens.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture(perform: resignFocus)

            HStack {
                Spacer()
                Button(action: openAccessibilityPermission) {
                    Text(UIStrings.Translate.openAccessibility)
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

    private func openAccessibilityPermission() {
        if SelectionCapture.hasAccessibilityTrust() {
            SelectionCapture.openAccessibilitySettings()
        } else {
            SelectionCapture.requestAccessibilityTrust()
        }
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
