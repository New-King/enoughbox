import AppKit
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var labelKey: LocalizedStringKey {
        switch self {
        case .system: "theme.system"
        case .light: "theme.light"
        case .dark: "theme.dark"
        }
    }

    var resolvedColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var iconName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    static var stored: AppearanceMode {
        let raw = UserDefaults.standard.string(forKey: "appearance") ?? AppearanceMode.system.rawValue
        return AppearanceMode(rawValue: raw) ?? .system
    }

    var effectiveColorScheme: ColorScheme {
        switch self {
        case .system:
            if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return .dark
            }
            return .light
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

@MainActor
final class AppearanceManager: ObservableObject {
    private enum Keys {
        static let appearance = "appearance"
    }

    @Published var mode: AppearanceMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Keys.appearance) }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Keys.appearance) ?? AppearanceMode.system.rawValue
        mode = AppearanceMode(rawValue: raw) ?? .system
    }

    func cycle() {
        switch mode {
        case .system: mode = .light
        case .light: mode = .dark
        case .dark: mode = .system
        }
    }
}
