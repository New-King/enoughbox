import AppKit
import SwiftUI

@MainActor
final class ClipboardTool {
    static let id = "com.enoughbox.clipboard"

    private let store = ClipboardStore()
    private var panelController: ClipboardPanelController?

    func activate() {
        store.startMonitoring()
        HotkeyCenter.shared.register(HotkeyCatalog.clipboardPanelID) { [weak self] in
            self?.togglePanel()
        }
    }

    func deactivate() {
        HotkeyCenter.shared.unregister(HotkeyCatalog.clipboardPanelID)
        panelController?.close()
        panelController = nil
        store.stopMonitoring()
        store.endPanelSession()
    }

    private func togglePanel() {
        if panelController?.isVisible == true {
            panelController?.close()
            return
        }
        if panelController == nil {
            panelController = ClipboardPanelController(store: store)
        }
        panelController?.present()
    }
}

struct ClipboardSettingsView: View {
    @Environment(\.designTokens) private var tokens
    @State private var historyLimit = ClipboardSettings.historyLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UIStrings.Clipboard.settingsSection)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.inkMuted)
                .textCase(.uppercase)

            Picker(UIStrings.Clipboard.historyLimit, selection: $historyLimit) {
                ForEach(ClipboardLimits.allowedHistoryLimits, id: \.self) { limit in
                    Text(String(format: UIStrings.Clipboard.historyLimitFormat, limit)).tag(limit)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: historyLimit) { _, newValue in
                ClipboardSettings.historyLimit = newValue
            }

            Text(UIStrings.Clipboard.settingsHint)
                .font(.system(size: 11))
                .foregroundStyle(tokens.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tokens.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tokens.border, lineWidth: 1)
        )
    }
}
