import Foundation

protocol Translator: Sendable {
    func translate(_ text: String, from: TranslateLanguage, to: TranslateLanguage) async throws -> String
}

enum TranslationEngine: String, CaseIterable, Identifiable {
    case youdao
    case deepseek
    case system

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .youdao: UIStrings.Translate.engineYoudao
        case .deepseek: UIStrings.Translate.engineDeepSeek
        case .system: UIStrings.Translate.engineSystem
        }
    }

    /// Session-only cycle: Youdao → DeepSeek → System → Youdao.
    func next() -> TranslationEngine {
        let all = Array(Self.allCases)
        guard let index = all.firstIndex(of: self) else { return self }
        return all[(index + 1) % all.count]
    }
}

enum TranslatorError: LocalizedError {
    case emptyInput
    case missingYoudaoCredentials
    case missingDeepSeekKey
    case invalidURL
    case network
    case timeout
    case cancelled
    case systemUnavailable
    case systemFailed
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return UIStrings.Translate.errorEmpty
        case .missingYoudaoCredentials:
            return UIStrings.Translate.errorMissingYoudao
        case .missingDeepSeekKey:
            return UIStrings.Translate.errorMissingDeepSeek
        case .invalidURL:
            return UIStrings.Translate.errorInvalidURL
        case .network:
            return UIStrings.Translate.errorNetwork
        case .timeout:
            return UIStrings.Translate.errorTimeout
        case .cancelled:
            return UIStrings.Translate.errorCancelled
        case .systemUnavailable:
            return UIStrings.Translate.errorSystemUnavailable
        case .systemFailed:
            return UIStrings.Translate.errorSystemFailed
        case .provider(let message):
            return message
        }
    }
}

enum TranslateLanguage: String, CaseIterable, Identifiable {
    case auto = "auto"
    case zhHans = "zh-Hans"
    case en

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .auto:
            return UIStrings.Translate.languageAuto
        case .zhHans:
            return UIStrings.Translate.languageZhHans
        case .en:
            return UIStrings.Translate.languageEn
        }
    }

    var speechLanguage: String {
        switch self {
        case .auto: return "en-US"
        case .zhHans: return "zh-CN"
        case .en: return "en-US"
        }
    }

    var youdaoCode: String {
        switch self {
        case .auto: return "en"
        case .zhHans: return "zh-CHS"
        case .en: return "en"
        }
    }

    var appleIdentifier: String { rawValue }

    var englishLabel: String {
        switch self {
        case .auto: return "Detected language"
        case .zhHans: return "Simplified Chinese"
        case .en: return "English"
        }
    }

    func resolvedTarget(for source: TranslateLanguage) -> TranslateLanguage {
        guard self == .auto else { return self }
        return source == .zhHans ? .en : .zhHans
    }
}

enum TranslateSettings {
    private static let targetKey = "com.enoughbox.translate.targetLanguage"
    private static let engineKey = "com.enoughbox.translate.engine"
    private static let youdaoAppIDKey = "com.enoughbox.translate.youdao.appID"
    private static let youdaoAppSecretKey = "com.enoughbox.translate.youdao.appSecret"
    private static let youdaoAPIKeyKey = "com.enoughbox.translate.youdao.apiKey"
    private static let deepSeekAPIKeyKey = "com.enoughbox.translate.deepseek.apiKey"
    private static let deepSeekURLKey = "com.enoughbox.translate.deepseek.baseURL"
    private static let deepSeekModelKey = "com.enoughbox.translate.deepseek.model"

    static let defaultDeepSeekURL = "https://api.deepseek.com/chat/completions"
    static let defaultDeepSeekModel = "deepseek-v4-flash"

    static var targetLanguage: TranslateLanguage {
        get {
            TranslateLanguage(rawValue: UserDefaults.standard.string(forKey: targetKey) ?? "") ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: targetKey)
        }
    }

    static var engine: TranslationEngine {
        get {
            TranslationEngine(rawValue: UserDefaults.standard.string(forKey: engineKey) ?? "") ?? .youdao
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: engineKey)
        }
    }

    static var deepSeekBaseURL: String {
        get {
            let value = UserDefaults.standard.string(forKey: deepSeekURLKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty || value == "https://api.deepseek.com" {
                return defaultDeepSeekURL
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue, forKey: deepSeekURLKey)
        }
    }

    static var deepSeekModel: String {
        get {
            let value = UserDefaults.standard.string(forKey: deepSeekModelKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? defaultDeepSeekModel : value
        }
        set {
            UserDefaults.standard.set(newValue, forKey: deepSeekModelKey)
        }
    }

    static var youdaoAppID: String {
        get { stored(youdaoAppIDKey) }
        set { setStored(newValue, key: youdaoAppIDKey) }
    }

    static var youdaoAppSecret: String {
        get { stored(youdaoAppSecretKey) }
        set { setStored(newValue, key: youdaoAppSecretKey) }
    }

    static var youdaoAPIKey: String {
        get { stored(youdaoAPIKeyKey) }
        set { setStored(newValue, key: youdaoAPIKeyKey) }
    }

    static var deepSeekAPIKey: String {
        get { stored(deepSeekAPIKeyKey) }
        set { setStored(newValue, key: deepSeekAPIKeyKey) }
    }

    static func translator(for engine: TranslationEngine) throws -> any Translator {
        switch engine {
        case .system:
            throw TranslatorError.systemUnavailable
        case .youdao:
            let resolvedID = youdaoAppID.isEmpty ? youdaoAPIKey : youdaoAppID
            guard !resolvedID.isEmpty, !youdaoAppSecret.isEmpty else {
                throw TranslatorError.missingYoudaoCredentials
            }
            return YoudaoTranslator(appKey: resolvedID, appSecret: youdaoAppSecret)
        case .deepseek:
            guard !deepSeekAPIKey.isEmpty else { throw TranslatorError.missingDeepSeekKey }
            return DeepSeekTranslator(
                apiKey: deepSeekAPIKey,
                model: deepSeekModel,
                baseURL: deepSeekBaseURL
            )
        }
    }

    private static func stored(_ key: String) -> String {
        UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func setStored(_ value: String, key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
    }
}

enum TranslationHTTP {
    static let timeout: TimeInterval = 30

    static func session(timeout: TimeInterval = timeout) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    static func data(for request: URLRequest, timeout: TimeInterval = timeout) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session(timeout: timeout).data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw TranslatorError.network }
            return (data, http)
        } catch is CancellationError {
            throw TranslatorError.cancelled
        } catch let error as TranslatorError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw TranslatorError.timeout
        } catch let error as URLError where error.code == .cancelled {
            throw TranslatorError.cancelled
        } catch {
            throw TranslatorError.network
        }
    }

    static func formURLEncoded(_ pairs: [String: String]) -> Data {
        pairs
            .map { key, value in
                "\(encode(key))=\(encode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum LanguageDetector {
    private static let sampleLimit = 50

    static func detect(_ text: String) -> TranslateLanguage {
        var hanCount = 0
        var latinCount = 0

        for scalar in text.unicodeScalars.prefix(sampleLimit) {
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                hanCount += 1
            case 0x41...0x5A, 0x61...0x7A:
                latinCount += 1
            default:
                continue
            }
        }

        return hanCount > latinCount ? .zhHans : .en
    }
}
