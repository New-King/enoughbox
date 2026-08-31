import AppKit

struct ScreenshotScrollingRegion: Sendable {
    /// Global Cocoa rect (`NSWindow.convertToScreen`), same as ScrollSnap's overlay `rectangle`.
    let rectangle: NSRect
    let scale: CGFloat
}

enum ScreenshotScrollingSupport {
    static func makeRegion(rectangle: NSRect, screen: NSScreen) -> ScreenshotScrollingRegion? {
        guard !rectangle.isEmpty else { return nil }
        return ScreenshotScrollingRegion(rectangle: rectangle, scale: screen.backingScaleFactor)
    }
}
