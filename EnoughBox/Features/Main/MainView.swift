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
        .toolbar { toolbarContent }
        .sheet(isPresented: $appState.isPluginStorePresented) {
            PluginStoreView()
                .designTokensProvider()
        }
        .overlay(alignment: .bottom) {
            if let toastMessage = appState.toastMessage {
                toast(message: toastMessage)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.toastMessage)
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $appState.selectedPluginID) {
            Section {
                if appState.installedPlugins.isEmpty {
                    Text("empty.sidebar.hint")
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.inkFaint)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(appState.installedPlugins) { plugin in
                        Label {
                            Text(plugin.localizedNameKey)
                        } icon: {
                            Image(systemName: plugin.iconName)
                        }
                        .tag(plugin.id)
                    }
                }
            } header: {
                Text("sidebar.section.tools")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(tokens.page)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            if let plugin = appState.selectedPlugin {
                PluginDetailView(plugin: plugin)
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
                appState.openPluginStore()
            } label: {
                Label("topbar.pluginStore", systemImage: "square.grid.2x2")
            }
            .help(String(localized: "topbar.pluginStore"))

            Menu {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        appearance.mode = mode
                    } label: {
                        Label(mode.labelKey, systemImage: mode.iconName)
                    }
                }
            } label: {
                Image(systemName: appearance.mode.iconName)
            }
            .help(String(localized: "topbar.appearance"))
        }
    }

    private func toast(message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tokens.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(tokens.border, lineWidth: 1)
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
