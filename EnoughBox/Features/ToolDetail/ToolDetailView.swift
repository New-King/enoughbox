import AppKit
import KeyboardShortcuts
import SwiftUI

struct ToolDetailView: View {
    @Environment(\.designTokens) private var tokens
    @EnvironmentObject private var appState: AppState

    let tool: EnabledTool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if tool.capabilities.contains(.hotkey),
                   let shortcutName = HotkeyCatalogHost.recorderName(forToolID: tool.id) {
                    shortcutCard(name: shortcutName, footerKey: shortcutFooterKey)
                }

                if let settings = appState.toolManager.settingsViewController(for: tool.id) {
                    toolSettingsCard(settings, toolID: tool.id)
                } else {
                    missingToolView
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .defaultScrollAnchor(.top)
        .background(tokens.shell)
        .navigationTitle(Text(appState.displayName(for: tool)))
        .onAppear {
            appState.toolManager.load(toolID: tool.id)
        }
    }

    private var shortcutFooterKey: LocalizedStringKey {
        switch tool.id {
        case "com.enoughbox.translate":
            "plugin.translate.shortcut.footer.active"
        default:
            "plugin.sample.shortcut.footer.active"
        }
    }

    private func shortcutCard(name: KeyboardShortcuts.Name, footerKey: LocalizedStringKey) -> some View {
        ToolShortcutSettingsCard(shortcutName: name, footerKey: footerKey)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(tokens.border, lineWidth: 1)
            )
    }

    private func toolSettingsCard(_ viewController: NSViewController, toolID: String) -> some View {
        ToolSettingsContainer(viewController: viewController)
            .id(toolID)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: tool.iconName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tokens.ink)
                .frame(width: 44, height: 44)
                .background(tokens.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(tokens.border, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(appState.displayName(for: tool))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tokens.ink)

                Text("v\(tool.version)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(tokens.inkMuted)
            }

            Spacer()
        }
    }

    private var missingToolView: some View {
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
                appState.openToolCenter()
            } label: {
                Text("plugin.detail.reinstall")
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct ToolSettingsContainer: NSViewControllerRepresentable {
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
    ToolDetailView(tool: EnabledTool(
        id: "com.enoughbox.translate",
        iconName: "character.book.closed",
        version: "0.1.0",
        capabilities: [.hotkey, .accessibility]
    ))
    .environmentObject(AppState.previewPopulated)
    .designTokensProvider()
    .frame(width: 560, height: 520)
}
