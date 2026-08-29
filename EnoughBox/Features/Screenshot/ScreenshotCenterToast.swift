import AppKit
import SwiftUI

/// Brief centered message after the screenshot session ends (e.g. color copied).
@MainActor
enum ScreenshotCenterToast {
    private static var activePanel: NSPanel?

    static func show(_ message: String) {
        closeActivePanel()

        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        guard let screen else { return }

        let colorScheme = AppearanceMode.stored.effectiveColorScheme
        let banner = FloatingBanner(message: message)
            .fixedSize()
            .preferredColorScheme(colorScheme)
            .designTokensProvider()

        let hosting = NSHostingView(rootView: banner)
        hosting.setFrameSize(hosting.fittingSize)

        let size = hosting.fittingSize
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
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.contentView = hosting

        panel.orderFrontRegardless()
        activePanel = panel

        let panelID = ObjectIdentifier(panel)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if let active = activePanel, ObjectIdentifier(active) == panelID {
                closeActivePanel()
            }
        }
    }

    private static func closeActivePanel() {
        activePanel?.contentView = nil
        activePanel?.close()
        activePanel = nil
    }
}
