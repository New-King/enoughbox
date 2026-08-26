import KeyboardShortcuts
import SwiftUI

/// Host-managed shortcut row. Kept outside `ScrollView` so the recorder receives clicks.
struct ToolShortcutSettingsCard: View {
    @Environment(\.designTokens) private var tokens
    @EnvironmentObject private var appState: AppState

    let shortcutName: KeyboardShortcuts.Name
    var footerKey: LocalizedStringKey = "plugin.sample.shortcut.footer.active"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("plugin.sample.section.shortcut")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.inkMuted)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                Text("plugin.sample.shortcut.placeholder")
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.inkSoft)

                Spacer(minLength: 8)

                ShortcutRecorderField(name: shortcutName) { shortcut in
                    let message = String(
                        format: String(localized: "plugin.shortcut.saved.format"),
                        "\(shortcut)"
                    )
                    appState.showToast(message)
                } onConflict: { conflict in
                    appState.showToast(conflict.localizedMessage, style: .error)
                }
                .frame(width: 140, height: 24)
            }

            Text(footerKey)
                .font(.system(size: 11))
                .foregroundStyle(tokens.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
