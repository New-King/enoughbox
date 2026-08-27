import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

private func isPlainKey(_ event: NSEvent, character: String) -> Bool {
    guard event.charactersIgnoringModifiers?.lowercased() == character.lowercased() else { return false }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return flags.intersection([.command, .control, .option]).isEmpty
}

private final class ScreenshotPanel: NSPanel {
    let overlayView: ScreenshotOverlayView

    init(screen: NSScreen, frozen: FrozenDisplay, pickableWindows: [ScreenshotGeometry.PickableWindow]) {
        let frame = screen.frame
        overlayView = ScreenshotOverlayView(
            frame: CGRect(origin: .zero, size: frame.size),
            frozen: frozen,
            pickableWindows: pickableWindows
        )
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        setFrame(frame, display: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        sharingType = .none
        hasShadow = false
        animationBehavior = .none
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false

        let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
        let imageView = NSImageView(frame: container.bounds)
        imageView.image = NSImage(cgImage: frozen.image, size: frame.size)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)
        overlayView.autoresizingMask = [.width, .height]
        container.addSubview(overlayView)
        contentView = container
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ScreenshotOverlayController {
    private(set) static var isSessionOnScreen = false

    var onCopied: ((String) -> Void)?
    var onSaved: ((String) -> Void)?
    var onFailed: (() -> Void)?

    private var panels: [ScreenshotPanel] = []
    private let pinController = ScreenshotPinController()
    private var sessionActive = false
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?

    func start() {
        guard !sessionActive, !Self.isSessionOnScreen else { return }
        sessionActive = true
        Self.isSessionOnScreen = true
        let protectedIDs = protectedWindowIDs()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let displays = try await ScreenCapture.freezeDisplays(protectedWindowIDs: protectedIDs)
                self.present(displays: displays, protectedWindowIDs: protectedIDs)
            } catch {
                self.endSession()
                DispatchQueue.main.async { [weak self] in
                    self?.onFailed?()
                }
            }
        }
    }

    func cancel() {
        dismiss(copyColor: false)
    }

    private func protectedWindowIDs() -> Set<CGWindowID> {
        pinController.protectedWindowIDs
    }

    private func present(displays: [FrozenDisplay], protectedWindowIDs: Set<CGWindowID>) {
        let mouse = NSEvent.mouseLocation
        var created: [ScreenshotPanel] = []
        for frozen in displays {
            let pickable = ScreenshotGeometry.pickableWindows(
                on: frozen.screen,
                protectedWindowIDs: protectedWindowIDs
            )
            let panel = ScreenshotPanel(screen: frozen.screen, frozen: frozen, pickableWindows: pickable)
            panel.overlayView.onAction = { [weak self] action in
                self?.handle(action, from: panel.overlayView)
            }
            created.append(panel)
        }
        panels = created
        for panel in created {
            panel.orderFrontRegardless()
        }
        installKeyMonitors()
        let active = created.first(where: { $0.frame.contains(mouse) }) ?? created.first
        active?.makeKey()
        if let view = active?.overlayView {
            active?.makeFirstResponder(view)
            view.bootstrap(atScreenPoint: mouse)
        }
        NSCursor.crosshair.set()
    }

    private func installKeyMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = event.window as? ScreenshotPanel else { return event }
            let view = panel.overlayView
            if event.keyCode == 53 {
                self.dismiss(copyColor: false)
                return nil
            }
            if !view.isSelectionCommitted {
                if isPlainKey(event, character: "c"),
                   let text = view.currentColorPasteboard() {
                    self.handle(.copyColor(text), from: view)
                    return nil
                }
                if event.charactersIgnoringModifiers == "/" {
                    view.cycleColorFormat()
                    return nil
                }
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            self?.dismiss(copyColor: false)
        }
    }

    private func removeKeyMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    private func markCapturePending() {
        panels.forEach { $0.overlayView.isCapturePending = true }
    }

    private func handle(_ action: ScreenshotOverlayAction, from view: ScreenshotOverlayView) {
        switch action {
        case .cancel:
            dismiss(copyColor: false)
        case .copyColor(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            dismiss(copyColor: true)
            ScreenshotCenterToast.show(UIStrings.Screenshot.toastColorCopied)
        case .confirm:
            guard let image = view.croppedImage() else {
                dismiss(copyColor: false)
                return
            }
            writePasteboard(image)
            dismiss(copyColor: false)
            let message = UIStrings.Screenshot.toastCopied
            DispatchQueue.main.async { [weak self] in
                self?.onCopied?(message)
            }
        case .save:
            guard let image = view.croppedImage() else { return }
            save(image)
        case .pin:
            guard let image = view.croppedImage() else { return }
            let screenRect = view.selectionScreenRect()
            let scale = view.displayScale
            pinController.pin(image, screenRect: screenRect, scale: scale)
            dismiss(copyColor: false)
        case .captureWindow(let windowID, let frame):
            markCapturePending()
            let scale = view.displayScale
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let image = await ScreenCapture.captureWindow(windowID, scale: scale) else {
                    view.isCapturePending = false
                    DispatchQueue.main.async { [weak self] in
                        self?.onFailed?()
                    }
                    return
                }
                view.applyWindowCapture(image, windowRect: frame)
            }
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
                let name = url.lastPathComponent
                DispatchQueue.main.async { [weak self] in
                    self?.onSaved?(name)
                }
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
        endSession()
        _ = copyColor
    }

    private func endSession() {
        removeKeyMonitors()
        NSCursor.arrow.set()
        for panel in panels {
            panel.makeFirstResponder(nil)
            panel.orderOut(nil)
        }
        panels = []
        sessionActive = false
        Self.isSessionOnScreen = false
        HostWindowFocus.returnToMainWindow()
    }

    /// Clears shielding-level overlay panels left after a failed or interrupted session.
    static func dismissOrphanedOverlayWindows() {
        guard !isSessionOnScreen else { return }
        for window in NSApp.windows {
            guard let panel = window as? NSPanel else { continue }
            guard panel.level.rawValue >= Int(CGShieldingWindowLevel()) else { continue }
            panel.orderOut(nil)
        }
        HostWindowFocus.returnToMainWindow()
    }
}

private enum ScreenshotOverlayAction {
    case cancel
    case confirm
    case save
    case pin
    case copyColor(String)
    case captureWindow(CGWindowID, CGRect)
}

private enum ResizeEdge {
    case n, s, e, w, ne, nw, se, sw, move
}

private final class ScreenshotOverlayView: NSView {
    private let frozen: FrozenDisplay
    private let pickableWindows: [ScreenshotGeometry.PickableWindow]
    private var workingImage: CGImage
    private var windowCaptureRect: CGRect?
    private var selection = CGRect.zero
    private var committed = false
    private var mosaicArmed = false
    private var dragStart: CGPoint?
    private var dragEdge: ResizeEdge?
    private var mosaicStart: CGPoint?
    private var isCustomDragging = false
    private var hoverPoint: CGPoint = .zero
    private var sampled: SampledColor?
    private var colorDisplayFormat: ColorDisplayFormat = .hex
    var isCapturePending = false
    var onAction: ((ScreenshotOverlayAction) -> Void)?

    var isSelectionCommitted: Bool { committed }
    var displayScale: CGFloat { frozen.screen.backingScaleFactor }

    func currentColorPasteboard() -> String? {
        sampled?.pasteboard(for: colorDisplayFormat)
    }

    func cycleColorFormat() {
        colorDisplayFormat = colorDisplayFormat.next
        refreshColorHUDContent()
    }

    private let toolbar = ScreenshotToolbar()
    private let colorHUD = ScreenshotColorHUD()

    init(frame: CGRect, frozen: FrozenDisplay, pickableWindows: [ScreenshotGeometry.PickableWindow]) {
        self.frozen = frozen
        self.pickableWindows = pickableWindows
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            applyChromeTheme()
        }
    }

    private func applyChromeTheme() {
        let tokens = DesignTokens.current
        toolbar.applyTheme(tokens)
        colorHUD.applyTheme(tokens)
    }

    func bootstrap(atScreenPoint screenPoint: CGPoint) {
        let local = CGPoint(
            x: screenPoint.x - frozen.screen.frame.origin.x,
            y: screenPoint.y - frozen.screen.frame.origin.y
        )
        hoverPoint = local
        applyWindowSnap(at: local)
        refreshColor()
        needsDisplay = true
    }

    func applyWindowCapture(_ image: CGImage, windowRect: CGRect) {
        workingImage = image
        windowCaptureRect = windowRect
        selection = windowRect
        isCapturePending = false
        commitSelection()
        needsDisplay = true
    }

    private var acceptsPointerInput: Bool {
        ScreenshotGeometry.selectionAcceptsPointerInput(capturePending: isCapturePending)
    }

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
        guard acceptsPointerInput else { return }
        hoverPoint = convert(event.locationInWindow, from: nil)
        refreshColor()
        if !committed, !isCustomDragging {
            applyWindowSnap(at: hoverPoint)
        }
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
        guard acceptsPointerInput else { return }
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
        isCustomDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard acceptsPointerInput else { return }
        let point = convert(event.locationInWindow, from: nil)
        hoverPoint = point
        refreshColor()
        if let mosaicStart, mosaicArmed {
            currentMosaicEnd = point
            needsDisplay = true
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
        if !isCustomDragging, !ScreenshotGeometry.isClick(from: start, to: point) {
            isCustomDragging = true
            selection = CGRect(origin: start, size: .zero)
        }
        guard isCustomDragging else { return }
        selection = ScreenshotGeometry.clamp(
            CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            ),
            to: bounds
        )
        colorHUD.isHidden = true
        needsDisplay = true
    }

    private var currentMosaicEnd: CGPoint?

    override func mouseUp(with event: NSEvent) {
        guard acceptsPointerInput else { return }
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
        guard let start = dragStart else { return }
        dragStart = nil
        if !committed {
            if isCustomDragging {
                if selection.width >= 8, selection.height >= 8 {
                    commitSelection()
                } else {
                    selection = .zero
                    isCustomDragging = false
                    applyWindowSnap(at: hoverPoint)
                    refreshColorHUDVisibility()
                }
            } else if ScreenshotGeometry.isClick(from: start, to: point),
                      let target = ScreenshotGeometry.window(at: point, in: pickableWindows) {
                onAction?(.captureWindow(target.windowID, target.frame))
            } else if ScreenshotGeometry.isClick(from: start, to: point) {
                selection = bounds
                commitSelection()
            } else {
                applyWindowSnap(at: point)
                if selection.width >= 8, selection.height >= 8 {
                    commitSelection()
                }
            }
        }
        isCustomDragging = false
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
        if isPlainKey(event, character: "c"),
           !committed,
           let text = currentColorPasteboard() {
            onAction?(.copyColor(text))
            return
        }
        if event.charactersIgnoringModifiers == "/" && !committed {
            cycleColorFormat()
            return
        }
        super.keyDown(with: event)
    }

    func croppedImage() -> CGImage? {
        guard !selection.isEmpty else { return nil }
        if let windowCaptureRect {
            return try? ScreenCapture.cropWithinWindow(
                workingImage,
                selection: selection,
                windowRect: windowCaptureRect,
                screenSize: bounds.size
            )
        }
        return try? ScreenCapture.crop(workingImage, localRect: selection, screenSize: bounds.size)
    }

    func selectionScreenRect() -> CGRect {
        guard !selection.isEmpty, let window else { return .zero }
        return window.convertToScreen(convert(selection, to: nil))
    }

    override func mouseExited(with event: NSEvent) {
        colorHUD.isHidden = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let dimAlpha: CGFloat = 0.36
        if selection.isEmpty {
            NSColor.black.withAlphaComponent(dimAlpha).setFill()
            bounds.fill()
        } else {
            let dim = NSBezierPath(rect: bounds)
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(dimAlpha).setFill()
            dim.fill()
            let borderRect = selection.insetBy(dx: 0.5, dy: 0.5)
            SelectionChrome.strokeAlternatingBorder(in: borderRect, lineWidth: committed ? 1 : 2)
            if committed {
                let edges: [ResizeEdge] = [.n, .s, .e, .w, .ne, .nw, .se, .sw]
                SelectionChrome.fillHandles(edges.map { handleRect($0) })
            }
            drawSizeBadge()
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
        let imageSize = CGSize(width: workingImage.width, height: workingImage.height)
        let pixel: CGRect
        if let windowCaptureRect {
            pixel = CropGeometry.cropRectWithinWindow(
                selection: localRect,
                windowRect: windowCaptureRect,
                screenSize: bounds.size,
                imageSize: imageSize
            )
        } else {
            pixel = CropGeometry.cropRect(
                localRect: localRect,
                screenSize: bounds.size,
                imageSize: imageSize
            )
        }
        workingImage = ScreenshotMosaic.apply(to: workingImage, pixelRect: pixel)
        needsDisplay = true
    }

    private func commitSelection() {
        committed = true
        toolbar.isHidden = false
        colorHUD.isHidden = true
        layoutChrome()
    }

    private func applyWindowSnap(at viewPoint: CGPoint) {
        if let window = ScreenshotGeometry.window(at: viewPoint, in: pickableWindows) {
            selection = window.frame
            return
        }
        selection = .zero
    }

    private func screenPoint(fromViewPoint viewPoint: CGPoint) -> CGPoint {
        guard let window = self.window else { return .zero }
        let windowPoint = convert(viewPoint, to: nil)
        return window.convertToScreen(CGRect(origin: windowPoint, size: .zero)).origin
    }

    private func refreshColorHUDVisibility() {
        colorHUD.isHidden = committed || isCustomDragging
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
    }

    private func drawSizeBadge() {
        let width = Int(selection.width.rounded())
        let height = Int(selection.height.rounded())
        guard width > 0, height > 0 else { return }
        let text = "\(width) × \(height) pt"
        let tokens = DesignTokens.current
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: tokens.ink.nsColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var rect = CGRect(
            x: selection.midX - size.width / 2 - 8,
            y: selection.maxY + 8,
            width: size.width + 16,
            height: size.height + 8
        )
        rect.origin.x = max(6, min(rect.origin.x, bounds.maxX - rect.width - 6))
        rect.origin.y = min(rect.origin.y, bounds.maxY - rect.height - 6)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        tokens.card.nsColor.withAlphaComponent(0.92).setFill()
        path.fill()
        tokens.border.nsColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        text.draw(
            at: CGPoint(x: rect.minX + 8, y: rect.minY + 4),
            withAttributes: attributes
        )
    }

    private func refreshColor() {
        sampled = PixelSampler.sample(image: frozen.image, viewPoint: hoverPoint, viewSize: bounds.size)
        if !committed, !isCustomDragging {
            refreshColorHUDContent()
            refreshColorHUDVisibility()
            placeColorHUD()
        }
    }

    private func refreshColorHUDContent() {
        guard sampled != nil else { return }
        let screenPoint = screenPoint(fromViewPoint: hoverPoint)
        colorHUD.update(
            sample: sampled,
            screenPoint: screenPoint,
            image: frozen.image,
            viewPoint: hoverPoint,
            viewSize: bounds.size,
            format: colorDisplayFormat
        )
    }

    private func placeColorHUD() {
        let size = colorHUD.fittingSize
        let margin: CGFloat = 12
        let offset: CGFloat = 18
        var origin = CGPoint(x: hoverPoint.x + offset, y: hoverPoint.y - size.height - offset)
        if origin.y < margin {
            origin.y = hoverPoint.y + offset
        }
        if origin.y + size.height > bounds.maxY - margin {
            origin.y = bounds.maxY - size.height - margin
        }
        if origin.x + size.width > bounds.maxX - margin {
            origin.x = hoverPoint.x - size.width - offset
        }
        if origin.x < margin {
            origin.x = margin
        }
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
        rect = ScreenshotGeometry.clamp(rect.standardized, to: bounds)
        if rect.width >= 8, rect.height >= 8 {
            selection = rect
        }
    }
}

private enum ColorDisplayFormat: CaseIterable {
    case hex
    case rgb
    case hsl

    var next: ColorDisplayFormat {
        let all = ColorDisplayFormat.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

private struct SampledColor {
    let hex: String
    let rgb: String
    let hsl: String
    let nsColor: NSColor

    func text(for format: ColorDisplayFormat) -> String {
        switch format {
        case .hex: hex
        case .rgb: rgb
        case .hsl: hsl
        }
    }

    func pasteboard(for format: ColorDisplayFormat) -> String {
        text(for: format)
    }
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
        let hsl = hslString(from: color)
        return SampledColor(hex: hex, rgb: rgb, hsl: hsl, nsColor: color)
    }

    private static func hslString(from color: NSColor) -> String {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let h = Int((hue * 360).rounded())
        let s = Int((saturation * 100).rounded())
        let l = Int((brightness * 100).rounded())
        return "hsl(\(h), \(s)%, \(l)%)"
    }
}

private enum SelectionChrome {
    private static let dash: [CGFloat] = [4, 4]

    static func strokeAlternatingBorder(in rect: CGRect, lineWidth: CGFloat) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = lineWidth
        let dash: [CGFloat] = [4, 4]
        NSColor.black.setStroke()
        path.setLineDash(dash, count: 2, phase: 0)
        path.stroke()
        NSColor.white.setStroke()
        path.setLineDash(dash, count: 2, phase: 4)
        path.stroke()
    }

    static func fillHandles(_ rects: [CGRect]) {
        for rect in rects {
            NSColor.black.setFill()
            NSBezierPath(rect: rect).fill()
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            outline.stroke()
        }
    }
}

private enum ScreenshotToolbarIcons {
    static func mosaic(size: CGFloat, tint: NSColor) -> NSImage {
        let dimension = size
        return NSImage(size: NSSize(width: dimension, height: dimension), flipped: false) { rect in
            let inset: CGFloat = 0.5
            let outer = rect.insetBy(dx: inset, dy: inset)
            let frame = NSBezierPath(roundedRect: outer, xRadius: 3.2, yRadius: 3.2)
            tint.setStroke()
            frame.lineWidth = 1.2
            frame.stroke()

            let inner = outer.insetBy(dx: 2.2, dy: 2.2)
            let halfW = inner.width / 2
            let halfH = inner.height / 2
            let topLeft = CGRect(x: inner.minX, y: inner.minY + halfH, width: halfW, height: halfH)
            let topRight = CGRect(x: inner.maxX - halfW, y: inner.minY + halfH, width: halfW, height: halfH)
            let bottomLeft = CGRect(x: inner.minX, y: inner.minY, width: halfW, height: halfH)
            let bottomRight = CGRect(x: inner.maxX - halfW, y: inner.minY, width: halfW, height: halfH)

            let light = tint
            let dark = tint.withAlphaComponent(0.28)
            light.setFill()
            NSBezierPath(rect: topLeft).fill()
            NSBezierPath(rect: bottomRight).fill()
            dark.setFill()
            NSBezierPath(rect: topRight).fill()
            NSBezierPath(rect: bottomLeft).fill()
            return true
        }
    }
}

private final class ScreenshotToolbarButton: NSButton {
    var isArmed = false
    private var isHovering = false
    private var hoverColor: NSColor?
    private var armedColor: NSColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        sendAction(on: .leftMouseUp)
    }

    required init?(coder: NSCoder) { nil }

    func applyChrome(tint: NSColor, hover: NSColor, armed: NSColor) {
        contentTintColor = tint
        hoverColor = hover
        armedColor = armed
        refreshChrome()
    }

    func setArmed(_ armed: Bool) {
        isArmed = armed
        refreshChrome()
    }

    private func refreshChrome() {
        if isArmed, let armedColor {
            layer?.backgroundColor = armedColor.cgColor
        } else if isHovering, let hoverColor {
            layer?.backgroundColor = hoverColor.cgColor
        } else {
            layer?.backgroundColor = nil
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        refreshChrome()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        refreshChrome()
    }
}

private final class ScreenshotToolbar: NSView {
    enum Item: Int, CaseIterable {
        case pin, mosaic, save, cancel, confirm
    }

    var onPick: ((Item) -> Void)?
    private var mosaicButton: ScreenshotToolbarButton?
    private var buttons: [ScreenshotToolbarButton] = []

    private let buttonSide: CGFloat = 32
    private let buttonSpacing: CGFloat = 2
    private let horizontalPadding: CGFloat = 8

    override var intrinsicContentSize: NSSize { fittingSize }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.94).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let items: [(Item, String?, String)] = [
            (.pin, "pin.fill", UIStrings.Screenshot.pin),
            (.mosaic, nil, UIStrings.Screenshot.mosaic),
            (.save, "square.and.arrow.down.fill", UIStrings.Screenshot.save),
            (.cancel, "xmark", UIStrings.Screenshot.cancel),
            (.confirm, "checkmark", UIStrings.Screenshot.confirm),
        ]

        for (item, symbol, tooltip) in items {
            let button = ScreenshotToolbarButton(frame: .zero)
            if let symbol {
                button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(symbolConfig)
            }
            button.toolTip = tooltip
            button.target = self
            button.tag = item.rawValue
            button.action = #selector(tap(_:))
            addSubview(button)
            buttons.append(button)
            if item == .mosaic { mosaicButton = button }
        }
    }

    required init?(coder: NSCoder) { nil }

    override var fittingSize: NSSize {
        let count = CGFloat(Item.allCases.count)
        let width = horizontalPadding * 2 + count * buttonSide + (count - 1) * buttonSpacing
        return NSSize(width: width, height: 40)
    }

    override func layout() {
        super.layout()
        var x = horizontalPadding
        let y = (bounds.height - buttonSide) / 2
        for button in buttons {
            button.frame = CGRect(x: x, y: y, width: buttonSide, height: buttonSide)
            x += buttonSide + buttonSpacing
        }
    }

    func applyTheme(_ tokens: DesignTokens) {
        layer?.backgroundColor = tokens.card.nsColor.withAlphaComponent(0.94).cgColor
        layer?.borderColor = tokens.border.nsColor.cgColor
        let hover = tokens.ink.nsColor.withAlphaComponent(0.1)
        let armed = tokens.border.nsColor
        let mosaicImage = ScreenshotToolbarIcons.mosaic(size: 14, tint: tokens.controlTint.nsColor)
        for button in buttons {
            if button === mosaicButton {
                button.image = mosaicImage
            }
            button.applyChrome(
                tint: tokens.controlTint.nsColor,
                hover: hover,
                armed: armed
            )
        }
    }

    func setMosaicArmed(_ armed: Bool) {
        mosaicButton?.setArmed(armed)
    }

    @objc private func tap(_ sender: ScreenshotToolbarButton) {
        guard let item = Item(rawValue: sender.tag) else { return }
        onPick?(item)
    }
}

private final class ScreenshotMagnifierView: NSView {
    private var sampleImage: CGImage?
    private var surfaceColor: NSColor = .white
    private var gridColor: NSColor = NSColor(white: 0.55, alpha: 0.22)
    private var focusStrokeColor: NSColor = NSColor(white: 0.12, alpha: 0.92)
    private let gridColumns = 11
    private let gridRows = 11

    func applyTheme(_ tokens: DesignTokens) {
        surfaceColor = tokens.card.nsColor
        gridColor = tokens.border.nsColor
        focusStrokeColor = tokens.ink.nsColor.withAlphaComponent(0.92)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(surfaceColor.cgColor)
        context.fill(bounds)

        guard let sampleImage else { return }

        context.saveGState()
        context.interpolationQuality = .none
        context.draw(sampleImage, in: bounds)
        context.restoreGState()

        let cellW = bounds.width / CGFloat(gridColumns)
        let cellH = bounds.height / CGFloat(gridRows)

        context.saveGState()
        context.setStrokeColor(gridColor.cgColor)
        context.setLineWidth(0.5)
        for column in 0...gridColumns {
            let x = CGFloat(column) * cellW
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: bounds.height))
        }
        for row in 0...gridRows {
            let y = CGFloat(row) * cellH
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        context.strokePath()
        context.restoreGState()

        let centerCol = gridColumns / 2
        let centerRow = gridRows / 2
        let focus = CGRect(
            x: CGFloat(centerCol) * cellW + 0.5,
            y: CGFloat(centerRow) * cellH + 0.5,
            width: cellW - 1,
            height: cellH - 1
        )
        context.setStrokeColor(focusStrokeColor.cgColor)
        context.setLineWidth(1.5)
        context.stroke(focus)
    }

    func update(image: CGImage, viewPoint: CGPoint, viewSize: CGSize) {
        let half = CGFloat(gridColumns) / 2
        let pixelRect = CropGeometry.cropRect(
            localRect: CGRect(
                x: viewPoint.x - half,
                y: viewPoint.y - half,
                width: CGFloat(gridColumns),
                height: CGFloat(gridRows)
            ),
            screenSize: viewSize,
            imageSize: CGSize(width: image.width, height: image.height)
        )
        sampleImage = image.cropping(to: pixelRect)
        needsDisplay = true
    }
}

private final class ScreenshotColorHUD: NSView {
    private let clipContainer = NSView(frame: .zero)
    private let magnifier = ScreenshotMagnifierView(frame: .zero)
    private let footerBar = NSView(frame: .zero)
    private let coordLabel = NSTextField(labelWithString: "")
    private let colorLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    private static let panelWidth: CGFloat = 136
    private static let magnifierHeight: CGFloat = 132
    private static let footerHeight: CGFloat = 44
    private static let hintHeight: CGFloat = 16
    private static let cornerRadius: CGFloat = 14

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.14).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: 6)
        layer?.shadowRadius = 14
        layer?.shadowOpacity = 1

        clipContainer.wantsLayer = true
        clipContainer.layer?.cornerRadius = Self.cornerRadius
        clipContainer.layer?.masksToBounds = true
        clipContainer.layer?.borderWidth = 0.5
        clipContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        clipContainer.layer?.backgroundColor = NSColor(white: 0.97, alpha: 1).cgColor

        magnifier.wantsLayer = true
        magnifier.layer?.masksToBounds = true

        footerBar.wantsLayer = true
        footerBar.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1).cgColor

        coordLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        coordLabel.textColor = NSColor(white: 0.96, alpha: 1)
        coordLabel.lineBreakMode = .byTruncatingTail
        colorLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        colorLabel.textColor = NSColor(white: 0.98, alpha: 1)
        colorLabel.lineBreakMode = .byTruncatingTail

        hintLabel.font = .systemFont(ofSize: 9, weight: .regular)
        hintLabel.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        hintLabel.alignment = .center
        hintLabel.stringValue = UIStrings.Screenshot.colorHints

        for field in [coordLabel, colorLabel, hintLabel] {
            field.backgroundColor = .clear
            field.isBezeled = false
        }

        addSubview(clipContainer)
        clipContainer.addSubview(magnifier)
        clipContainer.addSubview(footerBar)
        footerBar.addSubview(coordLabel)
        footerBar.addSubview(colorLabel)
        clipContainer.addSubview(hintLabel)
    }

    required init?(coder: NSCoder) { nil }

    func applyTheme(_ tokens: DesignTokens) {
        clipContainer.layer?.backgroundColor = tokens.card.nsColor.cgColor
        clipContainer.layer?.borderColor = tokens.border.nsColor.cgColor
        footerBar.layer?.backgroundColor = tokens.nav.nsColor.cgColor
        coordLabel.textColor = tokens.inkSoft.nsColor
        colorLabel.textColor = tokens.ink.nsColor
        hintLabel.textColor = tokens.inkMuted.nsColor
        magnifier.applyTheme(tokens)
    }

    override var fittingSize: NSSize {
        NSSize(
            width: Self.panelWidth,
            height: Self.magnifierHeight + Self.footerHeight + Self.hintHeight
        )
    }

    func update(
        sample: SampledColor?,
        screenPoint: CGPoint,
        image: CGImage,
        viewPoint: CGPoint,
        viewSize: CGSize,
        format: ColorDisplayFormat
    ) {
        guard let sample else {
            isHidden = true
            return
        }
        isHidden = false
        magnifier.update(image: image, viewPoint: viewPoint, viewSize: viewSize)
        coordLabel.stringValue = "(\(Int(screenPoint.x.rounded())), \(Int(screenPoint.y.rounded())))"
        colorLabel.stringValue = sample.text(for: format)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        clipContainer.frame = bounds
        let width = bounds.width
        let footerStackHeight = Self.footerHeight + Self.hintHeight
        magnifier.frame = CGRect(x: 0, y: footerStackHeight, width: width, height: Self.magnifierHeight)
        footerBar.frame = CGRect(x: 0, y: Self.hintHeight, width: width, height: Self.footerHeight)
        let inset: CGFloat = 10
        let labelWidth = width - inset * 2
        coordLabel.frame = CGRect(x: inset, y: 24, width: labelWidth, height: 14)
        colorLabel.frame = CGRect(x: inset, y: 8, width: labelWidth, height: 14)
        hintLabel.frame = CGRect(x: 6, y: 0, width: width - 12, height: Self.hintHeight)
    }
}
