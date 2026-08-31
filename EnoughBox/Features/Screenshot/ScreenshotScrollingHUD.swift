import AppKit
import QuartzCore
import SwiftUI

@MainActor
enum ScreenshotScrollingHUD {
    private static var panel: NSPanel?
    private static var model: Model?
    private static var previewPanel: NSPanel?
    private static var previewImageView: NSImageView?
    private static var previewAnchor = NSRect.zero

    static var windowNumber: CGWindowID? {
        guard let panel else { return nil }
        return CGWindowID(panel.windowNumber)
    }

    static func show(
        anchor: NSRect,
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        previewAnchor = anchor
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

    static func update(image: NSImage, height: Int) {
        guard model != nil else { return }
        model?.height = height
        presentPreview(image)
    }

    static func dismiss() {
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
        model = nil
        previewImageView?.image = nil
        previewPanel?.orderOut(nil)
        previewPanel?.contentView = nil
        previewPanel = nil
        previewImageView = nil
        previewAnchor = .zero
    }

    private static func presentPreview(_ image: NSImage) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let panel = ensurePreviewPanel()
        let frame = previewFrame(for: image)
        previewImageView?.image = image
        previewImageView?.frame = panel.contentView?.bounds.insetBy(dx: 3, dy: 3) ?? .zero
        if panel.frame.isEmpty || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1)
                panel.animator().setFrame(frame, display: true)
            }
        }
        previewImageView?.frame = panel.contentView?.bounds.insetBy(dx: 3, dy: 3) ?? .zero
        panel.orderFrontRegardless()
    }

    private static func previewFrame(for image: NSImage) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(previewAnchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let columnWidth: CGFloat = 128
        let padding: CGFloat = 3
        let maxHeight = visible.height * 0.75
        let aspect = image.size.height / image.size.width
        var innerHeight = columnWidth * aspect
        if innerHeight > maxHeight - padding * 2 {
            innerHeight = maxHeight - padding * 2
        }
        let size = NSSize(width: columnWidth + padding * 2, height: innerHeight + padding * 2)

        var x = previewAnchor.maxX + 12
        if x + size.width > visible.maxX - 8 {
            x = previewAnchor.minX - size.width - 12
        }
        if x < visible.minX + 8 {
            x = max(visible.minX + 8, visible.maxX - size.width - 16)
        }

        var y = previewAnchor.maxY - size.height
        if y < visible.minY + 8 {
            y = visible.minY + 8
        }
        if y + size.height > visible.maxY - 8 {
            y = visible.maxY - size.height - 8
        }
        return NSRect(origin: CGPoint(x: x, y: y), size: size)
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

    private static func ensurePreviewPanel() -> NSPanel {
        if let previewPanel { return previewPanel }
        let panel = PreviewPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.setAccessibilityLabel(UIStrings.Screenshot.scrollingPreview)

        let tokens = DesignTokens.current
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.cornerRadius = 11
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = tokens.card.nsColor.cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = tokens.border.nsColor.cgColor
        container.autoresizingMask = [.width, .height]

        let imageView = NSImageView(frame: .zero)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignTop
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        container.addSubview(imageView)

        panel.contentView = container
        previewPanel = panel
        previewImageView = imageView
        return panel
    }

    private final class HUDPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private final class PreviewPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
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
