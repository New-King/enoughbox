import SwiftUI

struct EmptyStateView: View {
    @Environment(\.designTokens) private var tokens
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Text(UIStrings.App.slogan)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(tokens.inkFaint)
                    .italic()

                Text(UIStrings.Shell.emptyTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tokens.ink)
                    .padding(.top, 4)

                Text(UIStrings.Shell.emptySubtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(tokens.inkMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)

                Button {
                    appState.openToolCenter()
                } label: {
                    Text(UIStrings.Shell.openBuiltInTools)
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
