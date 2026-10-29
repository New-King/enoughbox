import Foundation

/// 通过免费开源词典接口查询英文单词的音标。
///
/// 只在「单个英文单词」时触发：句子、中文、数字串直接返回 nil。
/// 任何失败（网络、限流、词不存在）都静默返回 nil，不影响翻译主流程。
enum PhoneticService {
    private static let endpoint = "https://api.dictionaryapi.dev/api/v2/entries/en/"
    private static let timeout: TimeInterval = 8
    private static let maxWordLength = 45

    /// 复用连接：每次新建 ephemeral session 都要重新握手，是之前偶发失败的来源之一。
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    /// 同一个词只查一次；查不到的词也缓存空串，避免反复发无效请求。
    private static let cache = NSCache<NSString, NSString>()
    private static let missMarker = NSString(string: "")

    /// 划词常带句末标点（`succeeded.`、`(hello)`），先剥掉首尾非字母字符。
    static func normalizedWord(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = trimmed.drop(while: { !$0.isLetter })
        let tail = String(head.reversed().drop(while: { !$0.isLetter }).reversed())
        return tail
    }

    /// 是否值得查询：剥掉标点后只含英文字母，允许词内连字符与撇号（如 well-known、don't）。
    static func isLookupCandidate(_ text: String) -> Bool {
        let word = normalizedWord(text)
        guard !word.isEmpty, word.count <= maxWordLength else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-'")
        return word.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func lookup(_ text: String) async -> String? {
        let word = normalizedWord(text)
        guard isLookupCandidate(word) else { return nil }

        let key = NSString(string: word.lowercased())
        if let cached = cache.object(forKey: key) {
            return cached.length > 0 ? (cached as String) : nil
        }

        guard let encoded = word.lowercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: endpoint + encoded) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let phonetic = parse(data) else {
                cache.setObject(missMarker, forKey: key)
                return nil
            }
            cache.setObject(NSString(string: phonetic), forKey: key)
            return phonetic
        } catch {
            return nil
        }
    }

    /// 响应里音标有两种落点：顶层 `phonetic`，或 `phonetics[].text`（带英美差异）。
    private static func parse(_ data: Data) -> String? {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        for entry in entries {
            if let phonetic = entry["phonetic"] as? String, !phonetic.isEmpty {
                return phonetic
            }
            if let phonetics = entry["phonetics"] as? [[String: Any]] {
                for item in phonetics {
                    if let text = item["text"] as? String, !text.isEmpty {
                        return text
                    }
                }
            }
        }
        return nil
    }
}
