import AppKit
import CoreGraphics
import UniformTypeIdentifiers

private final class ScreenshotPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ScreenshotOverlayController {
    var onCopied: ((String) -> Void)?
    var onSaved: ((String) -> Void)?
    var onPermissionDenied: (() -> Void)?
    var onFailed: (() -> Void)?

    private var panels: [ScreenshotPanel] = []
    private let pinController = ScreenshotPinController()
    private var sessionActive = false

    func start() {
        guard !sessionActive else { return }
        if !ScreenCapture.requestAccess() {
            onPermissionDenied?()
            return
        }
        sessionActive = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let frames = try await ScreenCapture.freezeDisplays()
                self.present(frames: frames)
            } catch {
                self.sessionActive = false
                self.onFailed?()
            }
        }
    }

    func cancel() {
        dismiss(copyColor: false)
    }

    private func present(frames: [FrozenDisplay]) {
        let mouse = NSEvent.mouseLocation
        var created: [ScreenshotPanel] = []
        for frame in frames {
            let view = ScreenshotOverlayView(
                frame: CGRect(origin: .zero, size: frame.screen.frame.size),
                frozen: frame
            )
            view.onAction = { [weak self] action in
                self?.handle(action, from: view)
            }
            let panel = ScreenshotPanel(
                contentRect: frame.screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.setFrame(frame.screen.frame, display: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.sharingType = .none
            panel.hasShadow = false
            panel.animationBehavior = .none
            panel.acceptsMouseMovedEvents = true
            panel.ignoresMouseEvents = false
            panel.contentView = view
            created.append(panel)
        }
        panels = created
        for panel in created {
            panel.orderFrontRegardless()
        }
        let active = created.first(where: { $0.frame.contains(mouse) }) ?? created.first
        active?.makeKey()
        if let view = active?.contentView as? ScreenshotOverlayView {
            active?.makeFirstResponder(view)
        }
        NSCursor.crosshair.set()
    }

    private func handle(_ action: ScreenshotOverlayAction, from view: ScreenshotOverlayView) {
        switch action {
        case .cancel:
            dismiss(copyColor: false)
        case .copyColor(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            dismiss(copyColor: true)
            onCopied?(String(format: ScreenshotL10n.string("plugin.screenshot.toast.color"), text))
        case .confirm:
            guard let image = view.croppedImage() else {
                dismiss(copyColor: false)
                return
            }
            writePasteboard(image)
            dismiss(copyColor: false)
            onCopied?(ScreenshotL10n.string("plugin.screenshot.toast.copied"))
        case .save:
            guard let image = view.croppedImage() else { return }
            save(image)
        case .pin:
            guard let image = view.croppedImage() else { return }
            dismiss(copyColor: false)
            pinController.pin(image)
        }
    }

    private func save(_ image: CGImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFileName()
        let overlays = panels
        for overlay in overlays { overlay.orderOut(nil) }
        panel.begin { [weak self] response in
            guard let self else { return }
            if response == .OK, let url = panel.url, let data = pngData(image) {
                try? data.write(to: url)
                self.dismiss(copyColor: false)
                self.onSaved?(url.lastPathComponent)
            } else {
                for overlay in overlays { overlay.orderFrontRegardless() }
            }
        }
    }

    private func writePasteboard(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        pasteboard.writeObjects([nsImage])
    }

    private func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "EnoughBox-\(formatter.string(from: Date())).png"
    }

    private func dismiss(copyColor: Bool) {
        NSCursor.arrow.set()
        for panel in panels {
            panel.orderOut(nil)
        }
        panels = []
        sessionActive = false
        _ = copyColor
    }
}

private enum ScreenshotOverlayAction {
    case cancel
    case confirm
    case save
    case pin
    case copyColor(String)
}

private enum ResizeEdge {
    case n, s, e, w, ne, nw, se, sw, move
}

private final class ScreenshotOverlayView: NSView {
    private let frozen: FrozenDisplay
    private var workingImage: CGImage
    private var selection = CGRect.zero
    private var committed = false
    private var mosaicArmed = false
    private var dragStart: CGPoint?
    private var dragEdge: ResizeEdge?
    private var mosaicStart: CGPoint?
    private var hoverPoint: CGPoint = .zero
    private var sampled: SampledColor?
    var onAction: ((ScreenshotOverlayAction) -> Void)?

    private let toolbar = ScreenshotToolbar()
    private let colorHUD = ScreenshotColorHUD()

    init(frame: CGRect, frozen: FrozenDisplay) {
        self.frozen = frozen
        self.workingImage = frozen.image
        super.init(frame: frame)
        wantsLayer = true
        addSubview(toolbar)
        addSubview(colorHUD)
        toolbar.isHidden = true
        toolbar.onPick = { [weak self] item in
            self?.handleToolbar(item)
        }
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        hoverPoint = convert(event.locationInWindow, from: nil)
        refreshColor()
        if committed, !mosaicArmed {
            window?.invalidateCursorRects(for: self)
        }
        needsDisplay = true
    }

    override func resetCursorRects() {
        if mosaicArmed {
            addCursorRect(bounds, cursor: .crosshair)
            return
        }
        if committed {
            addCursorRect(selection, cursor: .openHand)
            for edge in [ResizeEdge.n, .s, .e, .w, .ne, .nw, .se, .sw] {
                addCursorRect(handleRect(edge), cursor: cursor(for: edge))
            }
        } else {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if committed {
            if let edge = hitHandle(point) {
                dragEdge = edge
                dragStart = point
                return
            }
            if mosaicArmed, selection.contains(point) {
                mosaicStart = point
                return
            }
            if selection.contains(point) {
                dragEdge = .move
                dragStart = point
                return
            }
            return
        }
        dragStart = point
        selection = CGRect(origin: point, size: .zero)
        committed = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hoverPoint = point
        refreshColor()
        if let mosaicStart, mosaicArmed {
            needsDisplay = true
            self.mosaicStart = mosaicStart
            currentMosaicEnd = point
            return
        }
        if committed, let edge = dragEdge, let start = dragStart {
            applyResize(edge: edge, from: start, to: point)
            dragStart = point
            layoutChrome()
            needsDisplay = true
            return
        }
        guard let start = dragStart, !committed else { return }
        selection = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        needsDisplay = true
    }

    private var currentMosaicEnd: CGPoint?

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let mosaicStart, mosaicArmed {
            let rect = CGRect(
                x: min(mosaicStart.x, point.x),
                y: min(mosaicStart.y, point.y),
                width: abs(point.x - mosaicStart.x),
                height: abs(point.y - mosaicStart.y)
            ).intersection(selection)
            if rect.width >= 4, rect.height >= 4 {
                bakeMosaic(rect)
            }
            self.mosaicStart = nil
            currentMosaicEnd = nil
            needsDisplay = true
            return
        }
        dragEdge = nil
        dragStart = nil
        if !committed, selection.width >= 8, selection.height >= 8 {
            committed = true
            toolbar.isHidden = false
            layoutChrome()
        } else if !committed {
            selection = .zero
        }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onAction?(.cancel)
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            if committed { onAction?(.confirm) }
            return
        }
        if event.charactersIgnoringModifiers == "/" {
            if let sampled {
                onAction?(.copyColor(sampled.pasteboard))
            } else {
                onAction?(.cancel)
            }
            return
        }
        super.keyDown(with: event)
    }

    func currentColorText() -> String? {
        sampled?.pasteboard
    }

    func croppedImage() -> CGImage? {
        guard !selection.isEmpty else { return nil }
        return try? ScreenCapture.crop(workingImage, localRect: selection, screenSize: bounds.size)
    }

    override func mouseExited(with event: NSEvent) {
        colorHUD.isHidden = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let image = NSImage(cgImage: workingImage, size: bounds.size)
        image.draw(in: bounds)
        if selection.isEmpty {
            NSColor.black.withAlphaComponent(0.36).setFill()
            bounds.fill()
        } else {
            let dim = NSBezierPath(rect: bounds)
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.36).setFill()
            dim.fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            if committed {
                NSColor.white.setFill()
                for edge in [ResizeEdge.n, .s, .e, .w, .ne, .nw, .se, .sw] {
                    NSBezierPath(rect: handleRect(edge)).fill()
                }
            }
        }
        drawMosaicPreviewIfNeeded()
    }

    override func layout() {
        super.layout()
        layoutChrome()
    }

    private func drawMosaicPreviewIfNeeded() {
        guard let mosaicStart, let currentMosaicEnd else { return }
        let rect = CGRect(
            x: min(mosaicStart.x, currentMosaicEnd.x),
            y: min(mosaicStart.y, currentMosaicEnd.y),
            width: abs(currentMosaicEnd.x - mosaicStart.x),
            height: abs(currentMosaicEnd.y - mosaicStart.y)
        ).intersection(selection)
        NSColor.white.withAlphaComponent(0.2).setFill()
        rect.fill()
    }

    private func bakeMosaic(_ localRect: CGRect) {
        let pixel = CropGeometry.cropRect(
            localRect: localRect,
            screenSize: bounds.size,
            imageSize: CGSize(width: workingImage.width, height: workingImage.height)
        )
        workingImage = ScreenshotMosaic.apply(to: workingImage, pixelRect: pixel)
        needsDisplay = true
    }

    private func handleToolbar(_ item: ScreenshotToolbar.Item) {
        switch item {
        case .mosaic:
            mosaicArmed.toggle()
            toolbar.setMosaicArmed(mosaicArmed)
            window?.invalidateCursorRects(for: self)
        case .pin:
            onAction?(.pin)
        case .save:
            onAction?(.save)
        case .cancel:
            onAction?(.cancel)
        case .confirm:
            onAction?(.confirm)
        }
    }

    private func layoutChrome() {
        guard committed, !selection.isEmpty else { return }
        let barSize = toolbar.fittingSize
        var origin = CGPoint(x: selection.maxX - barSize.width, y: selection.minY - barSize.height - 8)
        if origin.y < 8 {
            origin.y = min(bounds.maxY - barSize.height - 8, selection.maxY + 8)
        }
        origin.x = min(max(8, origin.x), bounds.maxX - barSize.width - 8)
        toolbar.frame = CGRect(origin: origin, size: barSize)
        placeColorHUD()
    }

    private func refreshColor() {
        sampled = PixelSampler.sample(image: frozen.image, viewPoint: hoverPoint, viewSize: bounds.size)
        colorHUD.update(sampled)
        placeColorHUD()
    }

    private func placeColorHUD() {
        let size = colorHUD.fittingSize
        var origin = CGPoint(x: hoverPoint.x + 16, y: hoverPoint.y - size.height - 16)
        origin.x = min(max(8, origin.x), bounds.maxX - size.width - 8)
        origin.y = min(max(8, origin.y), bounds.maxY - size.height - 8)
        colorHUD.frame = CGRect(origin: origin, size: size)
    }

    private func handleRect(_ edge: ResizeEdge) -> CGRect {
        let s: CGFloat = 8
        let r = selection
        switch edge {
        case .n: return CGRect(x: r.midX - s / 2, y: r.maxY - s / 2, width: s, height: s)
        case .s: return CGRect(x: r.midX - s / 2, y: r.minY - s / 2, width: s, height: s)
        case .e: return CGRect(x: r.maxX - s / 2, y: r.midY - s / 2, width: s, height: s)
        case .w: return CGRect(x: r.minX - s / 2, y: r.midY - s / 2, width: s, height: s)
        case .ne: return CGRect(x: r.maxX - s / 2, y: r.maxY - s / 2, width: s, height: s)
        case .nw: return CGRect(x: r.minX - s / 2, y: r.maxY - s / 2, width: s, height: s)
        case .se: return CGRect(x: r.maxX - s / 2, y: r.minY - s / 2, width: s, height: s)
        case .sw: return CGRect(x: r.minX - s / 2, y: r.minY - s / 2, width: s, height: s)
        case .move: return .zero
        }
    }

    private func hitHandle(_ point: CGPoint) -> ResizeEdge? {
        for edge in [ResizeEdge.se, .sw, .ne, .nw, .e, .w, .n, .s] {
            if handleRect(edge).insetBy(dx: -3, dy: -3).contains(point) { return edge }
        }
        return nil
    }

    private func cursor(for edge: ResizeEdge) -> NSCursor {
        switch edge {
        case .n, .s: return .resizeUpDown
        case .e, .w: return .resizeLeftRight
        default: return .crosshair
        }
    }

    private func applyResize(edge: ResizeEdge, from: CGPoint, to: CGPoint) {
        var rect = selection
        let dx = to.x - from.x
        let dy = to.y - from.y
        switch edge {
        case .n: rect.size.height += dy
        case .s:
            rect.origin.y += dy
            rect.size.height -= dy
        case .e: rect.size.width += dx
        case .w:
            rect.origin.x += dx
            rect.size.width -= dx
        case .ne:
            rect.size.width += dx
            rect.size.height += dy
        case .nw:
            rect.origin.x += dx
            rect.size.width -= dx
            rect.size.height += dy
        case .se:
            rect.size.width += dx
            rect.origin.y += dy
            rect.size.height -= dy
        case .sw:
            rect.origin.x += dx
            rect.size.width -= dx
            rect.origin.y += dy
            rect.size.height -= dy
        case .move:
            rect.origin.x += dx
            rect.origin.y += dy
        }
        rect = rect.standardized.intersection(bounds)
        if rect.width >= 8, rect.height >= 8 {
            selection = rect
        }
    }
}

private struct SampledColor {
    let hex: String
    let rgb: String
    var pasteboard: String { "\(hex)  \(rgb)" }
    let nsColor: NSColor
}

private enum PixelSampler {
    static func sample(image: CGImage, viewPoint: CGPoint, viewSize: CGSize) -> SampledColor? {
        let rect = CropGeometry.cropRect(
            localRect: CGRect(origin: viewPoint, size: CGSize(width: 1, height: 1)),
            screenSize: viewSize,
            imageSize: CGSize(width: image.width, height: image.height)
        )
        guard !rect.isEmpty, let pixel = image.cropping(to: rect) else { return nil }
        let rep = NSBitmapImageRep(cgImage: pixel)
        guard let color = rep.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return nil }
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        let hex = String(format: "#%02X%02X%02X", r, g, b)
        let rgb = "rgb(\(r), \(g), \(b))"
        return SampledColor(hex: hex, rgb: rgb, nsColor: color)
    }
}

private final class ScreenshotToolbar: NSView {
    enum Item { case mosaic, pin, save, cancel, confirm }
    var onPick: ((Item) -> Void)?
    private var mosaicButton: NSButton?

    override var intrinsicContentSize: NSSize { fittingSize }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.92).cgColor
        layer?.cornerRadius = 11
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let items: [(Item, String, String)] = [
            (.mosaic, "square.grid.3x3.fill", "plugin.screenshot.action.mosaic"),
            (.pin, "pin", "plugin.screenshot.action.pin"),
            (.save, "square.and.arrow.down", "plugin.screenshot.action.save"),
            (.cancel, "xmark", "plugin.screenshot.action.cancel"),
            (.confirm, "checkmark", "plugin.screenshot.action.confirm"),
        ]
        var x: CGFloat = 6
        for (item, symbol, key) in items {
            let button = NSButton(frame: CGRect(x: x, y: 4, width: 28, height: 28))
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: ScreenshotL10n.string(key))
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.contentTintColor = .white
            button.toolTip = ScreenshotL10n.string(key)
            button.target = self
            button.tag = items.firstIndex(where: { $0.0 == item }) ?? 0
            button.sendAction(on: .leftMouseUp)
            button.action = #selector(tap(_:))
            addSubview(button)
            if item == .mosaic { mosaicButton = button }
            x += 30
        }
        setFrameSize(NSSize(width: x + 2, height: 36))
    }

    required init?(coder: NSCoder) { nil }

    override var fittingSize: NSSize { NSSize(width: 6 + 30 * 5 + 2, height: 36) }

    func setMosaicArmed(_ armed: Bool) {
        mosaicButton?.contentTintColor = armed ? NSColor(white: 0.85, alpha: 1) : .white
        mosaicButton?.layer?.backgroundColor = armed
            ? NSColor.white.withAlphaComponent(0.18).cgColor
            : nil
    }

    @objc private func tap(_ sender: NSButton) {
        let items: [Item] = [.mosaic, .pin, .save, .cancel, .confirm]
        guard items.indices.contains(sender.tag) else { return }
        onPick?(items[sender.tag])
    }
}

private final class ScreenshotColorHUD: NSView {
    private let swatch = NSView(frame: .zero)
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.92).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 4
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor(white: 0.9, alpha: 1)
        label.backgroundColor = .clear
        label.isBezeled = false
        addSubview(swatch)
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    override var fittingSize: NSSize { NSSize(width: 168, height: 28) }

    func update(_ sample: SampledColor?) {
        guard let sample else {
            isHidden = true
            return
        }
        isHidden = false
        swatch.layer?.backgroundColor = sample.nsColor.cgColor
        label.stringValue = sample.hex
        needsLayout = true
    }

    override func layout() {
        super.layout()
        swatch.frame = CGRect(x: 6, y: 6, width: 16, height: 16)
        label.frame = CGRect(x: 28, y: 4, width: bounds.width - 34, height: 20)
    }
}
