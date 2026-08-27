import Foundation

struct DeepSeekTranslator: Translator {
    private let apiKey: String
    private let model: String
    private let baseURL: String

    init(apiKey: String, model: String, baseURL: String) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    func translate(_ text: String, from: TranslateLanguage, to: TranslateLanguage) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslatorError.emptyInput }
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil, url.host != nil
        else {
            throw TranslatorError.invalidURL
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a translation engine. Translate the user's text from \(from.englishLabel) to \(to.englishLabel). Return only the translation, with no quotes or explanation.",
                ],
                [
                    "role": "user",
                    "content": trimmed,
                ],
            ],
            "thinking": ["type": "disabled"],
            "stream": false,
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await TranslationHTTP.data(for: request, timeout: 30)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if !(200...299).contains(http.statusCode) {
            if let error = payload?["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.isEmpty
            {
                throw TranslatorError.provider(message)
            }
            throw TranslatorError.provider(
                String(format: UIStrings.Translate.errorHTTPFormat, http.statusCode)
            )
        }

        let choices = payload?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = (message?["content"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { throw TranslatorError.systemFailed }
        return content
    }
}
