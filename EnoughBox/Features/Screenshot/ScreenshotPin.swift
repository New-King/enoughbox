import AppKit

private final class ScreenshotPinImageView: NSImageView {
    private var lastMouseLocation: CGPoint?

    override func mouseDown(with event: NSEvent) {
        lastMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let lastMouseLocation, let window else { return }
        let current = NSEvent.mouseLocation
        let delta = CGPoint(
            x: current.x - lastMouseLocation.x,
            y: current.y - lastMouseLocation.y
        )
        window.setFrameOrigin(CGPoint(
            x: window.frame.origin.x + delta.x,
            y: window.frame.origin.y + delta.y
        ))
        self.lastMouseLocation = current
    }

    override func mouseUp(with event: NSEvent) {
        lastMouseLocation = nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class ScreenshotPinController: NSObject, NSWindowDelegate {
    private var panels: [NSPanel] = []
    private let shadowPadding: CGFloat = 14

    var protectedWindowIDs: Set<CGWindowID> {
        Set(panels.compactMap { panel in
            panel.windowNumber > 0 ? CGWindowID(panel.windowNumber) : nil
        })
    }

    /// Places the pin at the on-screen selection rect so the image does not jump or rescale.
    func pin(_ image: CGImage, screenRect: CGRect, scale: CGFloat) {
        let logicalSize = CGSize(
            width: CGFloat(image.width) / scale,
            height: CGFloat(image.height) / scale
        )
        guard logicalSize.width > 0, logicalSize.height > 0 else { return }
        let paddedSize = CGSize(
            width: logicalSize.width + shadowPadding * 2,
            height: logicalSize.height + shadowPadding * 2
        )

        let imageView = ScreenshotPinImageView(frame: CGRect(origin: .zero, size: logicalSize))
        imageView.image = NSImage(cgImage: image, size: logicalSize)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter

        let container = NSView(frame: CGRect(origin: .zero, size: logicalSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        let luminance = averageLuminance(of: image)
        container.layer?.shadowColor = (luminance > 0.58 ? NSColor.black : NSColor.white).cgColor
        container.layer?.shadowOpacity = 0.14
        container.layer?.shadowRadius = 10
        container.layer?.shadowOffset = CGSize(width: 0, height: -2)
        imageView.autoresizingMask = [.width, .height]
        imageView.frame = CGRect(
            x: shadowPadding,
            y: shadowPadding,
            width: logicalSize.width,
            height: logicalSize.height
        )
        imageView.autoresizingMask = []
        container.addSubview(imageView)

        let panel = NSPanel(
            contentRect: NSRect(
                x: screenRect.minX - shadowPadding,
                y: screenRect.minY - shadowPadding,
                width: paddedSize.width,
                height: paddedSize.height
            ),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.minSize = CGSize(width: 48, height: 48)
        panel.contentAspectRatio = CGSize(width: image.width, height: image.height)
        panel.isOpaque = false
        panel.backgroundColor = .clear

        container.autoresizingMask = [.width, .height]
        panel.contentView = container
        panel.delegate = self
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setContentSize(paddedSize)
        panel.setFrameOrigin(CGPoint(
            x: screenRect.minX - shadowPadding,
            y: screenRect.minY - shadowPadding
        ))
        layoutPinContent(panel: panel, container: container, imageView: imageView)
        panel.orderFrontRegardless()
        panels.append(panel)
    }

    private func layoutPinContent(panel: NSPanel, container: NSView, imageView: NSImageView) {
        container.frame = panel.contentView?.bounds ?? container.frame
        container.layer?.masksToBounds = false
        let imageRect = container.bounds.insetBy(dx: shadowPadding, dy: shadowPadding)
        container.layer?.shadowPath = CGPath(rect: imageRect, transform: nil)
        imageView.frame = imageRect
    }

    private func averageLuminance(of image: CGImage) -> CGFloat {
        var pixel: UInt8 = 0
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 1,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return 1
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return CGFloat(pixel) / 255
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        panels.removeAll { $0 === panel }
    }
}
