import Foundation

enum ClipboardSettings {
    private static let historyLimitKey = "com.enoughbox.clipboard.historyLimit"
    private static let categoryKey = "com.enoughbox.clipboard.category"

    static var historyLimit: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: historyLimitKey)
            if stored == 0 {
                return ClipboardLimits.defaultHistoryLimit
            }
            return ClipboardLimits.sanitizedHistoryLimit(stored)
        }
        set {
            UserDefaults.standard.set(
                ClipboardLimits.sanitizedHistoryLimit(newValue),
                forKey: historyLimitKey
            )
        }
    }

    static var selectedCategory: ClipboardCategory {
        get {
            guard let raw = UserDefaults.standard.string(forKey: categoryKey),
                  let category = ClipboardCategory(rawValue: raw)
            else {
                return .recent
            }
            return category
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: categoryKey)
        }
    }
}
