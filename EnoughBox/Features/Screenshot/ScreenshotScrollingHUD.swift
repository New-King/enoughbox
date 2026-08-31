import AppKit
import SwiftUI

@MainActor
enum ScreenshotScrollingHUD {
    private static var panel: NSPanel?
    private static var model: Model?

    static var windowNumber: CGWindowID? {
        guard let panel else { return nil }
        return CGWindowID(panel.windowNumber)
    }

    static func show(
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let model = Model()
        self.model = model
        let host = NSHostingController(
            rootView: HUDView(
                model: model,
                onFinish: onFinish,
                onCancel: onCancel
            )
        )
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        let hudPanel = ensurePanel()
        hudPanel.contentViewController = host
        let frame = NSScreen.main?.visibleFrame ?? .zero
        hudPanel.setFrame(
            NSRect(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height - 24,
                width: size.width,
                height: size.height
            ),
            display: true
        )
        hudPanel.orderFrontRegardless()
    }

    static func update(height: Int) {
        model?.height = height
    }

    static func dismiss() {
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
        model = nil
    }

    private static func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = HUDPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.panel = panel
        return panel
    }

    private final class HUDPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private final class Model: ObservableObject {
        @Published var height = 0
    }

    private struct HUDView: View {
        @ObservedObject var model: Model
        let onFinish: () -> Void
        let onCancel: () -> Void

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.current.ink)
                VStack(alignment: .leading, spacing: 1) {
                    Text(UIStrings.Screenshot.scrollingProgress)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    Text("\(model.height) px")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button(UIStrings.Screenshot.cancel, action: onCancel)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button(UIStrings.Screenshot.scrollingDone, action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
