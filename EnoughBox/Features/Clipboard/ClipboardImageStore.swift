import AppKit
import Foundation
import ImageIO

enum ClipboardImageStore {
    private static let thumbnails: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    static func store(_ data: Data) -> String? {
        AppPaths.ensureClipboardDirectories()
        let name = UUID().uuidString + ".png"
        let url = AppPaths.clipboardImagesDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func imageData(named name: String) -> Data? {
        let url = AppPaths.clipboardImagesDirectory.appendingPathComponent(name)
        return try? Data(contentsOf: url)
    }

    static func thumbnail(named name: String) -> NSImage? {
        if let cached = thumbnails.object(forKey: name as NSString) {
            return cached
        }
        let url = AppPaths.clipboardImagesDirectory.appendingPathComponent(name)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        thumbnails.setObject(
            image,
            forKey: name as NSString,
            cost: cgImage.bytesPerRow * cgImage.height
        )
        return image
    }

    static func cleanup(keeping names: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: AppPaths.clipboardImagesDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where !names.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
            thumbnails.removeObject(forKey: file.lastPathComponent as NSString)
        }
    }

    static func clearCache() {
        thumbnails.removeAllObjects()
    }
}
