import Foundation

enum AppPaths {
    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("EnoughBox", isDirectory: true)
    }

    static var registryFile: URL {
        applicationSupport.appendingPathComponent("registry.json")
    }

    static var clipboardDirectory: URL {
        applicationSupport.appendingPathComponent("clipboard", isDirectory: true)
    }

    static var clipboardIndexFile: URL {
        clipboardDirectory.appendingPathComponent("index.json")
    }

    static var clipboardImagesDirectory: URL {
        clipboardDirectory.appendingPathComponent("images", isDirectory: true)
    }

    static var clipboardTextsDirectory: URL {
        clipboardDirectory.appendingPathComponent("texts", isDirectory: true)
    }

    static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
    }

    static func ensureClipboardDirectories() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: clipboardDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: clipboardImagesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: clipboardTextsDirectory, withIntermediateDirectories: true)
    }
}
