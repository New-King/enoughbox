import SwiftUI

/// App Store–style install control: pill when idle; ring only while busy (no digits).
struct PluginInstallButton: View {
    let plugin: StorePlugin

    @Environment(\.designTokens) private var tokens
    @EnvironmentObject private var appState: AppState

    private let ringSize: CGFloat = 32

    var body: some View {
        Group {
            if plugin.comingSoon {
                EmptyView()
            } else if appState.isInstalled(plugin) {
                uninstallControl
            } else {
                installControl
            }
        }
        .frame(width: 76, alignment: .trailing)
    }

    @ViewBuilder
    private var installControl: some View {
        switch appState.installPhase(for: plugin.id) {
        case nil:
            pillButton(title: "pluginStore.install") {
                appState.install(plugin)
            }

        case let .downloading(progress):
            circularProgressRing(progress: progress)

        case .installing:
            circularProgressRing(progress: nil)

        case .uninstalling:
            EmptyView()

        case .failed:
            pillButton(title: "pluginStore.retry") {
                appState.retryInstall(plugin)
            }
        }
    }

    @ViewBuilder
    private var uninstallControl: some View {
        if case .uninstalling = appState.installPhase(for: plugin.id) {
            circularProgressRing(progress: nil)
        } else {
            Button {
                if let installed = appState.installedPlugins.first(where: { $0.id == plugin.id }) {
                    appState.uninstall(installed)
                }
            } label: {
                Text("pluginStore.uninstall")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.inkMuted)
            }
            .buttonStyle(.plain)
        }
    }

    private func pillButton(title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(tokens.accent, in: Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    @ViewBuilder
    private func circularProgressRing(progress: Double?) -> some View {
        ZStack {
            Circle()
                .stroke(tokens.border, lineWidth: 2.5)

            if let progress {
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(
                        tokens.accent,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.12), value: progress)
            } else {
                IndeterminateRing(color: tokens.accent, lineWidth: 2.5)
            }
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: progress))
    }

    private func accessibilityLabel(for progress: Double?) -> Text {
        if progress != nil {
            return Text("pluginStore.downloading")
        }
        if appState.isInstalled(plugin) {
            return Text("pluginStore.uninstalling")
        }
        return Text("pluginStore.installing")
    }
}

private struct IndeterminateRing: View {
    let color: Color
    let lineWidth: CGFloat

    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.38)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

#Preview {
    HStack {
        Spacer()
        PluginInstallButton(plugin: StorePlugin.catalog[0])
    }
    .padding()
    .environmentObject(AppState())
    .designTokensProvider()
}
