import Foundation

enum MockTranslator {
    static func translate(_ text: String, to target: TranslateLanguage) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let note = TranslateL10n.string("plugin.translate.mock.note")
        if target == .zhHans, let mapped = englishToChinese[trimmed.lowercased()] {
            return "\(mapped)\n\n\(note)"
        }
        if target == .en, let mapped = chineseToEnglish[trimmed] {
            return "\(mapped)\n\n\(note)"
        }
        return "\(note)\n\(trimmed)"
    }

    private static let englishToChinese: [String: String] = [
        "hello": "你好",
        "hello.": "你好。",
        "hello pot.": "你好，锅。",
        "hello pot": "你好，锅",
    ]

    private static let chineseToEnglish: [String: String] = [
        "你好": "Hello",
        "你好。": "Hello.",
    ]
}

enum LanguageDetector {
    static func detect(_ text: String) -> TranslateLanguage {
        let cjk = text.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        return cjk * 4 >= max(text.count, 1) ? .zhHans : .en
    }
}
