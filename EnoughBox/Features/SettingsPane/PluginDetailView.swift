import AppKit
import KeyboardShortcuts
import SwiftUI

struct PluginDetailView: View {
    @Environment(\.designTokens) private var tokens
    @EnvironmentObject private var appState: AppState

    let plugin: InstalledPlugin

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 12)

            if plugin.capabilities.contains(.hotkey),
               let shortcutName = HotkeyCatalogHost.recorderName(forPluginID: plugin.id) {
                shortcutCard(name: shortcutName)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let settings = appState.pluginManager.settingsViewController(for: plugin.id) {
                        pluginSettingsCard(settings)
                    } else {
                        missingPluginView
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .background(tokens.shell)
        .navigationTitle(Text(appState.displayName(for: plugin)))
        .onAppear {
            appState.pluginManager.load(pluginID: plugin.id)
        }
    }

    private func shortcutCard(name: KeyboardShortcuts.Name) -> some View {
        PluginShortcutSettingsCard(shortcutName: name)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(tokens.border, lineWidth: 1)
            )
    }

    private func pluginSettingsCard(_ viewController: NSViewController) -> some View {
        PluginSettingsContainer(viewController: viewController)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .padding(16)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(tokens.border, lineWidth: 1)
            )
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
                Text(appState.displayName(for: plugin))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tokens.ink)

                Text("v\(plugin.version)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(tokens.inkMuted)
            }

            Spacer()
        }
    }

    private var missingPluginView: some View {
        VStack(spacing: 12) {
            Text("plugin.detail.missingBundle")
                .font(.system(size: 14))
                .foregroundStyle(tokens.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Text("plugin.detail.reinstallHint")
                .font(.system(size: 12))
                .foregroundStyle(tokens.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button {
                appState.openPluginStore()
            } label: {
                Text("plugin.detail.reinstall")
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct PluginSettingsContainer: NSViewControllerRepresentable {
    let viewController: NSViewController

    func makeCoordinator() -> Coordinator {
        Coordinator(viewController: viewController)
    }

    func makeNSViewController(context: Context) -> NSViewController {
        context.coordinator.viewController
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}

    final class Coordinator {
        let viewController: NSViewController

        init(viewController: NSViewController) {
            self.viewController = viewController
        }
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
