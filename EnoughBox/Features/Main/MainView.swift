import SwiftUI

struct MainView: View {
    @Environment(\.designTokens) private var tokens
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var appearance: AppearanceManager

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .background(tokens.page)
        .toolbarBackground(tokens.nav, for: .windowToolbar)
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
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $appState.selectedToolID) {
            Section {
                if appState.enabledTools.isEmpty {
                    Text("empty.sidebar.hint")
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.inkFaint)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(appState.enabledTools) { tool in
                        Label {
                            Text(appState.displayName(for: tool))
                        } icon: {
                            Image(systemName: tool.iconName)
                        }
                        .tag(tool.id)
                    }
                }
            } header: {
                Text("sidebar.section.tools")
            }
        }
        .listStyle(.sidebar)
        .contentMargins(.top, 8, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(tokens.page)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
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
            .help(String(localized: "topbar.pluginStore"))

            Menu {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        appearance.mode = mode
                    } label: {
                        HStack {
                            if appearance.mode == mode {
                                Image(systemName: "checkmark")
                            }
                            Text(mode.labelKey)
                        }
                    }
                }
            } label: {
                Image(systemName: appearance.mode.iconName)
            }
            .toolbarIconStyle(tokens)
            .help(String(localized: "topbar.appearance"))

        }
    }

    private func toast(message: String) -> some View {
        let isError = appState.toastStyle == .error
        return floatingBanner(
            message: message,
            foreground: isError ? tokens.danger : tokens.ink,
            border: isError ? tokens.danger.opacity(0.5) : tokens.border
        )
    }

    private func floatingBanner(message: String, foreground: Color, border: Color) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .appleShadow(tokens)
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
