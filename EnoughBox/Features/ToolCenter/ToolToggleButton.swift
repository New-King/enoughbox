import SwiftUI

/// App Store–style install control: pill when idle; ring only while busy (no digits).
struct ToolToggleButton: View {
    let tool: BuiltInTool

    @Environment(\.designTokens) private var tokens
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isEnabled(tool) {
                removeControl
            } else {
                enableControl
            }
        }
        .frame(width: 76, alignment: .trailing)
    }

    private var enableControl: some View {
        pillButton(title: UIStrings.ToolStore.install) {
            appState.enable(tool)
        }
    }

    private var removeControl: some View {
        Button {
            if let enabled = appState.enabledTools.first(where: { $0.id == tool.id }) {
                appState.remove(enabled)
            }
        } label: {
            Text(UIStrings.ToolStore.uninstall)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tokens.inkMuted)
        }
        .buttonStyle(.plain)
    }

    private func pillButton(title: String, action: @escaping () -> Void) -> some View {
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

}

#Preview {
    HStack {
        Spacer()
        ToolToggleButton(tool: BuiltInTool.catalog[0])
    }
    .padding()
    .environmentObject(AppState())
    .designTokensProvider()
}
