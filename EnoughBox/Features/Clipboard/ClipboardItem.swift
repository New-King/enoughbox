import Foundation

enum ClipboardItemKind: String, Codable, Sendable {
    case text
    case image
    case other
}

enum ClipboardCategory: String, CaseIterable, Identifiable {
    case recent
    case all
    case text
    case image
    case other

    var id: String { rawValue }
}

struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var copiedAt: Date
    var lastUsedAt: Date?
    let kind: ClipboardItemKind
    var text: String
    var imageFile: String?
    var imageHash: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var textFile: String?
    var filePaths: [String]

    init(
        id: UUID = UUID(),
        copiedAt: Date = Date(),
        kind: ClipboardItemKind,
        text: String = "",
        imageFile: String? = nil,
        imageHash: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        textFile: String? = nil,
        filePaths: [String] = [],
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.copiedAt = copiedAt
        self.lastUsedAt = lastUsedAt
        self.kind = kind
        self.text = text
        self.imageFile = imageFile
        self.imageHash = imageHash
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.textFile = textFile
        self.filePaths = filePaths
    }

    func resolvedText() -> String {
        if let textFile, let stored = ClipboardTextStore.read(named: textFile) {
            return stored
        }
        return text
    }

    var preview: String {
        switch kind {
        case .text:
            let source = resolvedText()
            let collapsed = source
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = String(collapsed.prefix(ClipboardLimits.previewCharacters))
            if prefix.count < collapsed.count {
                return prefix + "…"
            }
            return prefix.isEmpty ? String(source.prefix(ClipboardLimits.previewCharacters)) : prefix
        case .image:
            if let imageWidth, let imageHeight {
                return "\(imageWidth)×\(imageHeight)"
            }
            return UIStrings.Clipboard.imageEntry
        case .other:
            if !filePaths.isEmpty {
                return filePaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            }
            return text.isEmpty ? UIStrings.Clipboard.otherEntry : previewText(text)
        }
    }

    func matchesSearch(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        switch kind {
        case .text:
            return resolvedText().lowercased().contains(needle)
        case .image:
            return UIStrings.Clipboard.imageEntry.lowercased().contains(needle)
                || preview.lowercased().contains(needle)
        case .other:
            let haystack = ([text] + filePaths).joined(separator: " ").lowercased()
            return haystack.contains(needle)
        }
    }

    func matchesCategory(_ category: ClipboardCategory) -> Bool {
        switch category {
        case .recent, .all:
            return true
        case .text:
            return kind == .text
        case .image:
            return kind == .image
        case .other:
            return kind == .other
        }
    }

    private func previewText(_ value: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(collapsed.prefix(ClipboardLimits.previewCharacters))
        return prefix.count < collapsed.count ? prefix + "…" : prefix
    }
}

enum ClipboardLimits {
    static let previewCharacters = 120
    static let maxTextCharacters = 100_000
    static let recentCount = 20
    static let defaultHistoryLimit = 50
    static let allowedHistoryLimits = [20, 50, 100]
    static let maxCopiedFiles = 100
    static let maxImageBytes = 16 * 1024 * 1024
    static let maxRawImageBytes = 64 * 1024 * 1024
    static let concealedPasteboardType = "org.nspasteboard.ConcealedType"

    static func sanitizedHistoryLimit(_ value: Int) -> Int {
        allowedHistoryLimits.contains(value) ? value : defaultHistoryLimit
    }
}
