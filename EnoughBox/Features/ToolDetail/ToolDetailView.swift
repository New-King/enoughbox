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
                    .onTapGesture(perform: resignFocus)

                if tool.capabilities.contains(.hotkey),
                   let shortcutName = HotkeyCatalogHost.recorderName(forToolID: tool.id) {
                    shortcutCard(name: shortcutName, footer: shortcutFooter)
                }

                if tool.id == TranslateTool.id {
                    TranslateSettingsView()
                } else if tool.id == ScreenshotTool.id {
                    ScreenshotSettingsView()
                } else if tool.id == ClipboardTool.id {
                    ClipboardSettingsView()
                } else {
                    missingToolView
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                tokens.shell
                    .contentShape(Rectangle())
                    .onTapGesture(perform: resignFocus)
            }
        }
        .defaultScrollAnchor(.top)
        .background(tokens.shell)
        .navigationTitle(Text(appState.displayName(for: tool)))
        .onAppear {
            appState.toolManager.load(toolID: tool.id)
        }
    }

    private func resignFocus() {
        guard !HotkeyCenter.shared.isShortcutRecording else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private var shortcutFooter: String {
        switch tool.id {
        case "com.enoughbox.translate":
            UIStrings.Tool.translateShortcutFooter
        case "com.enoughbox.screenshot":
            UIStrings.Tool.screenshotShortcutFooter
        case "com.enoughbox.clipboard":
            UIStrings.Tool.clipboardShortcutFooter
        default:
            UIStrings.Shortcut.section
        }
    }

    private func shortcutCard(name: KeyboardShortcuts.Name, footer: String) -> some View {
        ToolShortcutSettingsCard(shortcutName: name, footer: footer)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tokens.card)
                    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .onTapGesture(perform: resignFocus)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(tokens.border, lineWidth: 1)
            )
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
            Text(UIStrings.Tool.missingBundle)
                .font(.system(size: 14))
                .foregroundStyle(tokens.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Text(UIStrings.Tool.reinstallHint)
                .font(.system(size: 12))
                .foregroundStyle(tokens.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button {
                appState.openToolCenter()
            } label: {
                Text(UIStrings.Tool.reinstall)
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

#Preview {
    ToolDetailView(tool: EnabledTool(
        id: "com.enoughbox.translate",
        iconName: "bubble.left",
        version: "0.1.0",
        capabilities: [.hotkey, .accessibility]
    ))
    .environmentObject(AppState.previewPopulated)
    .designTokensProvider()
    .frame(width: 560, height: 520)
}
