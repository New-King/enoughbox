import SwiftUI

struct PluginDetailView: View {
    @Environment(\.designTokens) private var tokens
    @EnvironmentObject private var appState: AppState

    let plugin: InstalledPlugin

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                settingsForm
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tokens.shell)
        .navigationTitle(Text(plugin.localizedNameKey))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: plugin.iconName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tokens.ink)
                .frame(width: 44, height: 44)
                .background(tokens.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(tokens.border, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.localizedNameKey)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tokens.ink)

                Text("v\(plugin.version)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(tokens.inkFaint)
            }

            Spacer()
        }
    }

    private var settingsForm: some View {
        Form {
            Section {
                HStack {
                    Text("plugin.sample.shortcut.placeholder")
                        .foregroundStyle(tokens.inkMuted)
                    Spacer()
                    Text("⌥⇧T")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(tokens.inkSoft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(tokens.border, lineWidth: 1)
                        )
                }
            } header: {
                Text("plugin.sample.section.shortcut")
            } footer: {
                Text("plugin.sample.shortcut.footer")
                    .foregroundStyle(tokens.inkFaint)
            }

            Section {
                Button {
                    appState.showToast(String(localized: "plugin.sample.toast"))
                } label: {
                    Text("plugin.sample.demoAction")
                }
            } header: {
                Text("plugin.sample.section.demo")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    PluginDetailView(plugin: InstalledPlugin(
        id: "com.enoughbox.sample",
        iconName: "puzzlepiece.extension",
        version: "0.1.0",
        capabilities: [.hotkey, .clipboard]
    ))
    .environmentObject(AppState.previewPopulated)
    .designTokensProvider()
    .frame(width: 560, height: 520)
}
