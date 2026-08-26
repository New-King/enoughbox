import CryptoKit
import Foundation

struct YoudaoTranslator: Translator {
    private let appKey: String
    private let appSecret: String
    private let endpoint = URL(string: "https://openapi.youdao.com/api")!

    init(appKey: String, appSecret: String) {
        self.appKey = appKey
        self.appSecret = appSecret
    }

    func translate(_ text: String, from: TranslateLanguage, to: TranslateLanguage) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslatorError.emptyInput }

        let salt = UUID().uuidString
        let curtime = String(Int(Date().timeIntervalSince1970))
        let sign = sha256Hex(appKey + truncate(trimmed) + salt + curtime + appSecret)
        let body = TranslationHTTP.formURLEncoded([
            "q": trimmed,
            "from": from.youdaoCode,
            "to": to.youdaoCode,
            "appKey": appKey,
            "salt": salt,
            "sign": sign,
            "signType": "v3",
            "curtime": curtime,
            "strict": "true",
        ])

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = TranslationHTTP.timeout
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, http) = try await TranslationHTTP.data(for: request)
        guard (200...299).contains(http.statusCode) else {
            throw TranslatorError.provider(
                String(format: TranslateL10n.string("plugin.translate.error.http"), http.statusCode)
            )
        }

        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let errorCode = payload?["errorCode"] as? String ?? ""
        guard errorCode == "0" else {
            throw TranslatorError.provider(youdaoMessage(for: errorCode))
        }
        let translations = payload?["translation"] as? [String]
        let result = translations?.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !result.isEmpty else { throw TranslatorError.systemFailed }
        return result
    }

    private func truncate(_ query: String) -> String {
        let ns = query as NSString
        let length = ns.length
        guard length > 20 else { return query }
        return ns.substring(with: NSRange(location: 0, length: 10))
            + "\(length)"
            + ns.substring(with: NSRange(location: length - 10, length: 10))
    }

    private func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func youdaoMessage(for code: String) -> String {
        switch code {
        case "102", "202":
            return TranslateL10n.string("plugin.translate.error.youdaoSign")
        case "401", "411", "412":
            return TranslateL10n.string("plugin.translate.error.youdaoQuota")
        default:
            return String(format: TranslateL10n.string("plugin.translate.error.youdaoCode"), code)
        }
    }
}
