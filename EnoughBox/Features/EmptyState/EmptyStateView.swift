import SwiftUI

struct EmptyStateView: View {
    @Environment(\.designTokens) private var tokens
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Text("app.slogan")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(tokens.inkFaint)
                    .italic()

                Text("empty.title")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tokens.ink)
                    .padding(.top, 4)

                Text("empty.subtitle")
                    .font(.system(size: 14))
                    .foregroundStyle(tokens.inkMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)

                Button {
                    appState.openPluginStore()
                } label: {
                    Text("empty.action.openStore")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(tokens.accent, in: Capsule())
                }
                .buttonStyle(PressScaleButtonStyle())
                .padding(.top, 12)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.shell)
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    EmptyStateView()
        .environmentObject(AppState())
        .designTokensProvider()
        .frame(width: 520, height: 480)
}
