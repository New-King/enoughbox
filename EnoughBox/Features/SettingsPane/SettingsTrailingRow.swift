import SwiftUI

/// Label on the left, fixed-width control pinned to the trailing edge.
struct SettingsTrailingRow<Control: View>: View {
    @Environment(\.designTokens) private var tokens

    let title: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.ink)
                Spacer(minLength: SettingsControlMetrics.width + 8)
            }

            control()
                .frame(
                    width: SettingsControlMetrics.width,
                    height: SettingsControlMetrics.height,
                    alignment: .trailing
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: SettingsControlMetrics.height)
    }
}
