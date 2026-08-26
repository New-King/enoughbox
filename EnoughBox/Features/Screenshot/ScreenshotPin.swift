import AppKit

@MainActor
final class ScreenshotPinController: NSObject, NSWindowDelegate {
    private var panels: [NSPanel] = []

    var protectedWindowIDs: Set<CGWindowID> {
        Set(panels.compactMap { panel in
            panel.windowNumber > 0 ? CGWindowID(panel.windowNumber) : nil
        })
    }

    /// Places the pin at the on-screen selection rect so the image does not jump or rescale.
    func pin(_ image: CGImage, screenRect: CGRect, scale: CGFloat) {
        let pointSize = screenRect.size
        guard pointSize.width > 0, pointSize.height > 0 else { return }

        let logicalSize = CGSize(
            width: CGFloat(image.width) / scale,
            height: CGFloat(image.height) / scale
        )

        let imageView = NSImageView(frame: CGRect(origin: .zero, size: pointSize))
        imageView.image = NSImage(cgImage: image, size: logicalSize)
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let panel = NSPanel(
            contentRect: screenRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.minSize = CGSize(width: 48, height: 48)
        panel.contentAspectRatio = CGSize(width: image.width, height: image.height)
        panel.contentView = imageView
        panel.delegate = self
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.orderFrontRegardless()
        panels.append(panel)
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        panels.removeAll { $0 === panel }
    }
}
