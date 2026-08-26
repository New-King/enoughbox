import AppKit

@MainActor
final class ScreenshotPinController: NSObject, NSWindowDelegate {
    private var panels: [NSPanel] = []

    func pin(_ image: CGImage) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let screen else { return }
        let pixelSize = CGSize(width: image.width, height: image.height)
        let maxSize = CGSize(
            width: min(620, screen.visibleFrame.width * 0.48),
            height: min(520, screen.visibleFrame.height * 0.58)
        )
        let scale = min(1, min(maxSize.width / max(pixelSize.width, 1), maxSize.height / max(pixelSize.height, 1)))
        let size = CGSize(
            width: max(160, pixelSize.width * scale),
            height: max(100, pixelSize.height * scale)
        )
        let origin = CGPoint(
            x: min(max(screen.visibleFrame.minX + 12, NSEvent.mouseLocation.x - size.width / 2), screen.visibleFrame.maxX - size.width - 12),
            y: min(max(screen.visibleFrame.minY + 12, NSEvent.mouseLocation.y - size.height / 2), screen.visibleFrame.maxY - size.height - 12)
        )

        let imageView = NSImageView(frame: CGRect(origin: .zero, size: size))
        imageView.image = NSImage(cgImage: image, size: size)
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let panel = NSPanel(
            contentRect: CGRect(origin: origin, size: size),
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
        panel.minSize = CGSize(width: 120, height: 80)
        panel.contentAspectRatio = pixelSize
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
