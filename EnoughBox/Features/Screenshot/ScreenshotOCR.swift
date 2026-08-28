import CoreGraphics
import Vision

enum ScreenshotOCR {
    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let accurate = try recognizeLines(
                in: image,
                level: .accurate,
                automaticallyDetectLanguage: true
            )
            if !accurate.isEmpty {
                return join(accurate)
            }

            let fast = try recognizeLines(
                in: image,
                level: .fast,
                automaticallyDetectLanguage: false
            )
            return join(fast)
        }.value
    }

    private static func recognizeLines(
        in image: CGImage,
        level: VNRequestTextRecognitionLevel,
        automaticallyDetectLanguage: Bool
    ) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = automaticallyDetectLanguage

        if let supported = try? request.supportedRecognitionLanguages() {
            let preferred = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
            let languages = preferred.filter { supported.contains($0) }
            if !languages.isEmpty {
                request.recognitionLanguages = languages
            }
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            return RecognizedLine(
                text: candidate.string,
                centerX: observation.boundingBox.midX,
                centerY: observation.boundingBox.midY
            )
        }
    }

    private static func join(_ lines: [RecognizedLine]) -> String {
        let sorted = lines.sorted {
            if abs($0.centerY - $1.centerY) > 0.018 {
                return $0.centerY > $1.centerY
            }
            return $0.centerX < $1.centerX
        }
        return sorted.map(\.text).joined(separator: "\n")
    }

    private struct RecognizedLine: Sendable {
        let text: String
        let centerX: CGFloat
        let centerY: CGFloat
    }
}
