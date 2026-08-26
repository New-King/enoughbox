import CoreGraphics

/// Maps an AppKit selection (points, bottom-left origin) onto a frozen
/// `CGImage` (pixels, top-left origin). Same coordinate contract used by
/// Aurora (MIT); kept local so Retina scale and y-flip stay testable.
enum CropGeometry {
    static func cropRect(localRect: CGRect, screenSize: CGSize, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, screenSize.width > 0, screenSize.height > 0 else {
            return .zero
        }
        let scaleX = imageSize.width / screenSize.width
        let scaleY = imageSize.height / screenSize.height
        return CGRect(
            x: localRect.minX * scaleX,
            y: (screenSize.height - localRect.maxY) * scaleY,
            width: localRect.width * scaleX,
            height: localRect.height * scaleY
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height))
    }

    /// Maps a selection inside a snapped window rect onto a window-only capture.
    static func cropRectWithinWindow(
        selection: CGRect,
        windowRect: CGRect,
        screenSize: CGSize,
        imageSize: CGSize
    ) -> CGRect {
        guard windowRect.width > 0, windowRect.height > 0 else { return .zero }
        let relative = CGRect(
            x: selection.minX - windowRect.minX,
            y: selection.minY - windowRect.minY,
            width: selection.width,
            height: selection.height
        )
        return cropRect(localRect: relative, screenSize: windowRect.size, imageSize: imageSize)
    }
}
