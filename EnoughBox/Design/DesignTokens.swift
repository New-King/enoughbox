import SwiftUI

struct DesignTokens: Equatable {
    let page: Color
    let shell: Color
    let nav: Color
    let card: Color
    let ink: Color
    let inkSoft: Color
    let inkMuted: Color
    let inkFaint: Color
    let accent: Color
    let accentHover: Color
    let accentSoft: Color
    let border: Color

    static func tokens(for colorScheme: ColorScheme) -> DesignTokens {
        colorScheme == .dark ? .dark : .light
    }

    static let light = DesignTokens(
        page: Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255),
        shell: Color.white,
        nav: Color.white,
        card: Color.white,
        ink: Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255),
        inkSoft: Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255),
        inkMuted: Color(red: 110 / 255, green: 110 / 255, blue: 115 / 255),
        inkFaint: Color(red: 134 / 255, green: 134 / 255, blue: 139 / 255),
        accent: Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255),
        accentHover: Color(red: 64 / 255, green: 64 / 255, blue: 64 / 255),
        accentSoft: Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255),
        border: Color.black.opacity(0.08)
    )

    static let dark = DesignTokens(
        page: Color(red: 36 / 255, green: 36 / 255, blue: 38 / 255),
        shell: Color(red: 52 / 255, green: 52 / 255, blue: 54 / 255),
        nav: Color(red: 29 / 255, green: 29 / 255, blue: 29 / 255),
        card: Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255),
        ink: Color(red: 224 / 255, green: 224 / 255, blue: 224 / 255),
        inkSoft: Color(red: 195 / 255, green: 195 / 255, blue: 199 / 255),
        inkMuted: Color(red: 168 / 255, green: 168 / 255, blue: 170 / 255),
        inkFaint: Color(red: 122 / 255, green: 122 / 255, blue: 125 / 255),
        accent: Color(red: 72 / 255, green: 72 / 255, blue: 73 / 255),
        accentHover: Color(red: 90 / 255, green: 90 / 255, blue: 91 / 255),
        accentSoft: Color(red: 38 / 255, green: 38 / 255, blue: 39 / 255),
        border: Color.white.opacity(0.08)
    )
}

private struct DesignTokensKey: EnvironmentKey {
    static let defaultValue = DesignTokens.light
}

extension EnvironmentValues {
    var designTokens: DesignTokens {
        get { self[DesignTokensKey.self] }
        set { self[DesignTokensKey.self] = newValue }
    }
}

struct DesignTokensProvider: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let tokens = DesignTokens.tokens(for: colorScheme)
        content
            .environment(\.designTokens, tokens)
            .tint(tokens.accent)
    }
}

extension View {
    func designTokensProvider() -> some View {
        modifier(DesignTokensProvider())
    }

    func appleShadow(_ tokens: DesignTokens) -> some View {
        shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.04), radius: 1.5, x: 0, y: 1)
    }

    func appleEaseAnimation<V: Equatable>(_ value: V) -> some View {
        animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.2), value: value)
    }
}
