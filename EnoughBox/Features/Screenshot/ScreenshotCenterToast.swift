import AppKit

/// Brief centered message after the screenshot session ends (e.g. color copied).
@MainActor
enum ScreenshotCenterToast {
    private static var activePanel: NSPanel?

    static func show(_ message: String) {
        activePanel?.orderOut(nil)

        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        guard let screen else { return }

        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (message as NSString).size(withAttributes: attributes)
        let horizontalPadding: CGFloat = 28
        let verticalPadding: CGFloat = 14
        let size = CGSize(
            width: textSize.width + horizontalPadding,
            height: textSize.height + verticalPadding
        )
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
        )

        let panel = NSPanel(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        let label = NSTextField(labelWithString: message)
        label.font = font
        label.textColor = NSColor(white: 0.95, alpha: 1)
        label.alignment = .center
        label.frame = CGRect(origin: .zero, size: size)

        let background = NSView(frame: CGRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.88).cgColor
        background.layer?.cornerRadius = size.height / 2
        background.addSubview(label)
        panel.contentView = background

        panel.orderFrontRegardless()
        activePanel = panel

        let panelID = ObjectIdentifier(panel)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if let active = activePanel, ObjectIdentifier(active) == panelID {
                active.orderOut(nil)
                activePanel = nil
            }
        }
    }
}
