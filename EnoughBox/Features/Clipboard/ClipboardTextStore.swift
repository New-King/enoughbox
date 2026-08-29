import Foundation

enum ClipboardTextStore {
    static let inlineLimit = 4_096

    static func store(_ text: String) -> String? {
        guard text.count > inlineLimit else { return nil }
        AppPaths.ensureClipboardDirectories()
        let name = UUID().uuidString + ".txt"
        let url = AppPaths.clipboardTextsDirectory.appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return name
        } catch {
            return nil
        }
    }

    static func read(named name: String) -> String? {
        let url = AppPaths.clipboardTextsDirectory.appendingPathComponent(name)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func cleanup(keeping names: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: AppPaths.clipboardTextsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where !names.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
