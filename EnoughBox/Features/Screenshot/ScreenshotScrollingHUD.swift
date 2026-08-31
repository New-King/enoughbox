import AppKit
import SwiftUI

@MainActor
enum ScreenshotScrollingHUD {
    private static let previewColumnWidth: CGFloat = 192
    private static let previewPadding: CGFloat = 3

    private static var panel: NSPanel?
    private static var model: Model?
    private static var previewPanel: NSPanel?
    private static var previewImageView: NSImageView?
    private static var previewAnchor = NSRect.zero
    private static var previewX: CGFloat?
    private static var previewTopY: CGFloat?
    private static var finishHandler: (() -> Void)?
    private static var cancelHandler: (() -> Void)?
    private static var localKeyMonitor: Any?
    private static var globalKeyMonitor: Any?

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
        hudPanel.setFrame(hudFrame(size: size, anchor: anchor), display: true)
        finishHandler = onFinish
        cancelHandler = onCancel
        installKeyMonitors()
        ScreenshotScrollingShade.show(hole: anchor)
        NSApp.activate(ignoringOtherApps: true)
        hudPanel.makeKeyAndOrderFront(nil)
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
        removeKeyMonitors()
        finishHandler = nil
        cancelHandler = nil
        ScreenshotScrollingShade.dismiss()
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
        previewX = nil
        previewTopY = nil
    }

    private static func presentPreview(_ image: NSImage) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let panel = ensurePreviewPanel()
        let screen = NSScreen.screens.first { $0.frame.intersects(previewAnchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let padding = previewPadding
        let columnWidth = previewColumnWidth
        let naturalHeight = columnWidth * (image.size.height / image.size.width)
        let maxInnerHeight = max(40, visible.height * 0.75 - padding * 2)
        let fits = naturalHeight <= maxInnerHeight
        let innerWidth: CGFloat
        let innerHeight: CGFloat
        if fits {
            innerWidth = columnWidth
            innerHeight = naturalHeight
        } else {
            let scale = min(columnWidth / image.size.width, maxInnerHeight / image.size.height)
            innerWidth = image.size.width * scale
            innerHeight = image.size.height * scale
        }
        let boxHeight = fits ? innerHeight : maxInnerHeight
        let panelSize = NSSize(
            width: columnWidth + padding * 2,
            height: boxHeight + padding * 2
        )

        if previewX == nil || previewTopY == nil {
            var x = previewAnchor.maxX + 12
            if x + panelSize.width > visible.maxX - 8 {
                x = previewAnchor.minX - panelSize.width - 12
            }
            if x < visible.minX + 8 {
                x = max(visible.minX + 8, visible.maxX - panelSize.width - 16)
            }
            var topY = previewAnchor.maxY
            if topY > visible.maxY - 8 {
                topY = visible.maxY - 8
            }
            previewX = x
            previewTopY = topY
        }

        var y = (previewTopY ?? visible.maxY) - panelSize.height
        if y < visible.minY + 8 {
            y = visible.minY + 8
            previewTopY = y + panelSize.height
        }

        panel.setFrame(
            NSRect(x: previewX ?? visible.maxX - panelSize.width - 16, y: y, width: panelSize.width, height: panelSize.height),
            display: true
        )

        let imageX = padding + (columnWidth - innerWidth) / 2
        let imageY = padding + (boxHeight - innerHeight) / 2
        previewImageView?.imageScaling = .scaleProportionallyUpOrDown
        previewImageView?.imageAlignment = .alignCenter
        previewImageView?.image = image
        previewImageView?.frame = NSRect(x: imageX, y: imageY, width: innerWidth, height: innerHeight)
        panel.orderFrontRegardless()
    }

    private static func hudFrame(size: NSSize, anchor: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let fallbackY = visible.maxY - size.height - 24
        let gap: CGFloat = 8
        let fitsAbove = anchor.maxY + gap + size.height <= visible.maxY - 4
        let almostFullScreen = anchor.height >= visible.height * 0.85
        var x = anchor.minX
        let minX = visible.minX + 8
        let maxX = visible.maxX - size.width - 8
        if maxX >= minX {
            x = min(max(x, minX), maxX)
        } else {
            x = visible.minX + 8
        }
        let y = (fitsAbove && !almostFullScreen) ? anchor.maxY + gap : fallbackY
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func installKeyMonitors() {
        removeKeyMonitors()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleCaptureKey(event) ? nil : event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = handleCaptureKey(event)
        }
    }

    @discardableResult
    private static func handleCaptureKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 36, 76:
            finishHandler?()
            return true
        case 53:
            cancelHandler?()
            return true
        default:
            return false
        }
    }

    private static func removeKeyMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
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
        imageView.wantsLayer = true
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

/// WeChat-style dim: everything except the live selection hole is shaded.
/// HUD / preview sit on a higher window level so they keep original brightness.
/// Capture excludes this app, so the shade does not appear in stitched frames.
/// Slabs around the hole swallow clicks; the hole has no window so scroll reaches the page.
@MainActor
private enum ScreenshotScrollingShade {
    private static let dimAlpha: CGFloat = 0.36
    private static let windowLevel = NSWindow.Level(rawValue: Int(NSWindow.Level.statusBar.rawValue) - 1)
    private static var panels: [NSPanel] = []

    static func show(hole: NSRect) {
        dismiss()
        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            let cut = hole.intersection(screenFrame)
            if cut.isNull || cut.width < 1 || cut.height < 1 {
                addFill(screenFrame)
                continue
            }
            let top = NSRect(x: screenFrame.minX, y: cut.maxY, width: screenFrame.width, height: max(0, screenFrame.maxY - cut.maxY))
            let bottom = NSRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: max(0, cut.minY - screenFrame.minY))
            let left = NSRect(x: screenFrame.minX, y: cut.minY, width: max(0, cut.minX - screenFrame.minX), height: cut.height)
            let right = NSRect(x: cut.maxX, y: cut.minY, width: max(0, screenFrame.maxX - cut.maxX), height: cut.height)
            for slab in [top, bottom, left, right] where slab.width >= 0.5 && slab.height >= 0.5 {
                addFill(slab)
            }
            addBorder(around: cut)
        }
        for panel in panels {
            panel.orderFrontRegardless()
        }
    }

    static func dismiss() {
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
        panels = []
    }

    private static func addFill(_ frame: NSRect) {
        let panel = ShadePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(panel, frame: frame, clickThrough: false)
        let fill = NSView(frame: panel.contentView?.bounds ?? .zero)
        fill.wantsLayer = true
        fill.layer?.backgroundColor = NSColor.black.withAlphaComponent(dimAlpha).cgColor
        fill.autoresizingMask = [.width, .height]
        panel.contentView = fill
        panels.append(panel)
    }

    private static func addBorder(around hole: NSRect) {
        let frame = hole.insetBy(dx: -2, dy: -2)
        let panel = ShadePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(panel, frame: frame, clickThrough: true)
        let border = ShadeBorderView(frame: panel.contentView?.bounds ?? .zero)
        border.autoresizingMask = [.width, .height]
        panel.contentView = border
        panels.append(panel)
    }

    private static func configure(_ panel: NSPanel, frame: NSRect, clickThrough: Bool) {
        panel.setFrame(frame, display: false)
        panel.level = windowLevel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = clickThrough
        panel.sharingType = .none
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    private final class ShadePanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class ShadeBorderView: NSView {
        override var isOpaque: Bool { false }

        override func draw(_ dirtyRect: NSRect) {
            let rect = bounds.insetBy(dx: 2.5, dy: 2.5)
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1
            let dash: [CGFloat] = [4, 4]
            NSColor.black.setStroke()
            path.setLineDash(dash, count: 2, phase: 0)
            path.stroke()
            NSColor.white.setStroke()
            path.setLineDash(dash, count: 2, phase: 4)
            path.stroke()
        }
    }
}
