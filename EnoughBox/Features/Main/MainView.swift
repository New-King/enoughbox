import SwiftUI

struct MainView: View {
    @Environment(\.designTokens) private var tokens
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var appearance: AppearanceManager

    /// 220pt − 25% ≈ 165pt
    private let sidebarWidth: CGFloat = 165

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .background(tokens.shell)
        .toolbarBackground(tokens.shell, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar { toolbarContent }
        .sheet(isPresented: $appState.isToolCenterPresented) {
            ToolCenterView()
                .designTokensProvider()
        }
        .overlay(alignment: .top) {
            if let toastMessage = appState.toastMessage {
                toast(message: toastMessage)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.toastMessage)
        .onAppear(perform: clearWindowFocus)
        .onChange(of: appState.selectedToolID) { _, _ in
            clearWindowFocus()
        }
    }

    private func clearWindowFocus() {
        DispatchQueue.main.async {
            guard !HotkeyCenter.shared.isShortcutRecording else { return }
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(UIStrings.Shell.toolsSection)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.inkMuted)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                if appState.enabledTools.isEmpty {
                    Text(UIStrings.Shell.noToolsEnabled)
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.inkFaint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                } else {
                    ForEach(appState.enabledTools) { tool in
                        ToolSidebarRow(
                            iconName: tool.iconName,
                            title: appState.displayName(for: tool),
                            isSelected: appState.selectedToolID == tool.id,
                            tokens: tokens,
                            onSelect: { appState.selectedToolID = tool.id }
                        )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(tokens.shell)
        .frame(width: sidebarWidth)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            if let tool = appState.selectedTool {
                ToolDetailView(tool: tool)
            } else {
                EmptyStateView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.shell)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                appState.openToolCenter()
            } label: {
                Image(systemName: "square.grid.2x2")
            }
            .toolbarIconStyle(tokens)
            .help(UIStrings.Shell.builtInTools)
            .id("toolbar-tools-\(appearance.mode.rawValue)")

            Menu {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        appearance.mode = mode
                    } label: {
                        HStack {
                            if appearance.mode == mode {
                                Image(systemName: "checkmark")
                            }
                            Text(mode.label)
                        }
                    }
                }
            } label: {
                Image(systemName: appearance.mode.iconName)
            }
            .toolbarIconStyle(tokens)
            .help(UIStrings.Shell.appearance)
            .id("toolbar-appearance-\(appearance.mode.rawValue)")

        }
    }

    private func toast(message: String) -> some View {
        let isError = appState.toastStyle == .error
        return FloatingBanner(
            message: message,
            foreground: isError ? tokens.danger : nil,
            border: isError ? tokens.danger.opacity(0.5) : nil
        )
    }
}

/// Sidebar tool row — selection highlight only; no List focus or press chrome.
private struct ToolSidebarRow: View {
    let iconName: String
    let title: String
    let isSelected: Bool
    let tokens: DesignTokens
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 16, alignment: .center)
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 0)
        }
        .foregroundStyle(
            isSelected
                ? Color(nsColor: .alternateSelectedControlTextColor)
                : tokens.ink
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .selectedContentBackgroundColor))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture(perform: onSelect)
    }
}

#Preview("Empty") {
    MainView()
        .environmentObject(AppState())
        .environmentObject(AppearanceManager())
        .designTokensProvider()
        .frame(width: 900, height: 620)
}

#Preview("With Plugin") {
    MainView()
        .environmentObject(AppState.previewPopulated)
        .environmentObject(AppearanceManager())
        .designTokensProvider()
        .frame(width: 900, height: 620)
}
