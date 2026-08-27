import SwiftUI

struct MainView: View {
    @Environment(\.designTokens) private var tokens
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var appearance: AppearanceManager

    /// 220pt − 25% ≈ 165pt
    private let sidebarWidth: CGFloat = 165

    private let sidebarRowInsets = EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            shellDivider
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

    private var shellDivider: some View {
        Rectangle()
            .fill(tokens.border)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private func clearWindowFocus() {
        DispatchQueue.main.async {
            guard !HotkeyCenter.shared.isShortcutRecording else { return }
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $appState.selectedToolID) {
            Section {
                if appState.enabledTools.isEmpty {
                    Text(UIStrings.Shell.noToolsEnabled)
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.inkFaint)
                        .padding(.vertical, 4)
                        .listRowInsets(sidebarRowInsets)
                } else {
                    ForEach(appState.enabledTools) { tool in
                        Label {
                            Text(appState.displayName(for: tool))
                        } icon: {
                            Image(systemName: tool.iconName)
                        }
                        .tag(tool.id)
                        .listRowInsets(sidebarRowInsets)
                    }
                }
            } header: {
                Text(UIStrings.Shell.toolsSection)
            }
        }
        .listStyle(.sidebar)
        .contentMargins(.top, 8, for: .scrollContent)
        .contentMargins(.bottom, 8, for: .scrollContent)
        .contentMargins(.horizontal, 4, for: .scrollContent)
        .scrollContentBackground(.hidden)
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
