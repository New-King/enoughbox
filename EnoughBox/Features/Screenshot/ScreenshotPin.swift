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

        let imageView = ScreenshotPinImageView(frame: CGRect(origin: .zero, size: logicalSize))
        imageView.image = NSImage(cgImage: image, size: logicalSize)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter

        let container = NSView(frame: CGRect(origin: .zero, size: logicalSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        imageView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)

        let panel = NSPanel(
            contentRect: NSRect(origin: screenRect.origin, size: logicalSize),
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
        panel.hasShadow = true
        panel.minSize = CGSize(width: 48, height: 48)
        panel.contentAspectRatio = CGSize(width: image.width, height: image.height)
        panel.isOpaque = true
        panel.backgroundColor = .black

        container.autoresizingMask = [.width, .height]
        panel.contentView = container
        panel.delegate = self
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setContentSize(logicalSize)
        panel.setFrameOrigin(screenRect.origin)
        layoutPinContent(panel: panel, container: container, imageView: imageView)
        panel.orderFrontRegardless()
        panels.append(panel)
    }

    private func layoutPinContent(panel: NSPanel, container: NSView, imageView: NSImageView) {
        container.frame = panel.contentView?.bounds ?? container.frame
        imageView.frame = container.bounds
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        panels.removeAll { $0 === panel }
    }
}
