import SwiftUI

/// Shared toast / banner chrome (main-window toast and screen-centered CenterToast).
struct FloatingBanner: View {
    @Environment(\.designTokens) private var tokens

    let message: String
    var foreground: Color?
    var border: Color?

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground ?? tokens.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(border ?? tokens.border, lineWidth: 1)
            )
            .appleShadow(tokens)
    }
}
