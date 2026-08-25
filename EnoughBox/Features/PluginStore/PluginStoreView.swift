import SwiftUI

struct PluginStoreView: View {
    @Environment(\.designTokens) private var tokens
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(StorePlugin.catalog) { plugin in
                        storeRow(plugin)
                    }
                }
                .padding(20)
            }
            .background(tokens.page)
        }
        .frame(width: 560, height: 520)
        .background(tokens.page)
    }

    private var header: some View {
        HStack {
            Text("pluginStore.title")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tokens.ink)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tokens.inkMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(tokens.nav)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tokens.border)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func storeRow(_ plugin: StorePlugin) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: plugin.iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(plugin.comingSoon ? tokens.inkFaint : tokens.ink)
                .frame(width: 40, height: 40)
                .background(tokens.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tokens.border, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(plugin.nameKey)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(plugin.comingSoon ? tokens.inkFaint : tokens.ink)

                    if plugin.comingSoon {
                        Text("pluginStore.comingSoon")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(tokens.inkFaint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(tokens.accentSoft, in: Capsule())
                    }
                }

                Text(plugin.descriptionKey)
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if !plugin.comingSoon {
                    Text("v\(plugin.version)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(tokens.inkFaint)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            PluginInstallButton(plugin: plugin)
        }
        .padding(16)
        .background(tokens.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(tokens.border, lineWidth: 1)
        )
        .appleShadow(tokens)
        .opacity(plugin.comingSoon ? 0.72 : 1)
    }
}

#Preview {
    PluginStoreView()
        .environmentObject(AppState())
        .designTokensProvider()
}
