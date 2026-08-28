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
    private var ocrGeneration = 0
    private let ocrResultPanel = ScreenshotOCRResultPanelController()
    private let translationController = TranslationPanelController()

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
        case .ocr:
            runOCR(from: view, openingTranslation: false)
        case .translate:
            runOCR(from: view, openingTranslation: true)
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

    private func runOCR(from view: ScreenshotOverlayView, openingTranslation: Bool) {
        guard let image = view.croppedImage() else { return }
        ocrGeneration += 1
        let generation = ocrGeneration
        view.setToolbarInteractionEnabled(false)
        ScreenshotCenterToast.show(UIStrings.Screenshot.ocrProcessing)

        Task { @MainActor [weak self, weak view] in
            do {
                let text = try await ScreenshotOCR.recognize(image)
                guard let self, self.ocrGeneration == generation else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.dismiss(copyColor: false)
                    ScreenshotCenterToast.show(UIStrings.Screenshot.ocrNoText)
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(trimmed, forType: .string)
                    self.dismiss(copyColor: false)
                    if openingTranslation {
                        self.translationController.present(sourceText: trimmed)
                    } else {
                        self.ocrResultPanel.present(text: trimmed)
                        ScreenshotCenterToast.show(UIStrings.Screenshot.ocrCopied)
                    }
                }
            } catch {
                guard let self, self.ocrGeneration == generation else { return }
                self.dismiss(copyColor: false)
                ScreenshotCenterToast.show(UIStrings.Screenshot.ocrFailed)
            }
            view?.setToolbarInteractionEnabled(true)
        }
    }

    private func save(_ image: CGImage) {
        guard let host = panels.first(where: { $0.isKeyWindow }) ?? panels.first else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.showsTagField = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFileName()
        panel.title = UIStrings.Screenshot.save
        panel.prompt = UIStrings.Screenshot.save

        NSApp.activate(ignoringOtherApps: true)
        host.makeKeyAndOrderFront(nil)
        panel.beginSheetModal(for: host) { [weak self] response in
            guard let self else { return }
            if response == .OK, let url = panel.url, let data = pngData(image) {
                try? data.write(to: url)
                self.dismiss(copyColor: false)
                let name = url.lastPathComponent
                DispatchQueue.main.async { [weak self] in
                    self?.onSaved?(name)
                }
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
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return "ScreenShot_\(formatter.string(from: Date())).png"
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
    case ocr
    case translate
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
    private var mosaicPainting = false
    private var mosaicBrushDiameter: CGFloat = 24
    private var lastMosaicPoint: CGPoint?
    private var dragStart: CGPoint?
    private var dragEdge: ResizeEdge?
    private var isCustomDragging = false
    private var hoverPoint: CGPoint = .zero
    private var sampled: SampledColor?
    private var colorDisplayFormat: ColorDisplayFormat = .hex
    var isCapturePending = false
    var onAction: ((ScreenshotOverlayAction) -> Void)?

    var isSelectionCommitted: Bool { committed }
    var displayScale: CGFloat { frozen.screen.backingScaleFactor }

    func setToolbarInteractionEnabled(_ enabled: Bool) {
        toolbar.setInteractionEnabled(enabled)
    }

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
        toolbar.onMosaicBrushDiameterChange = { [weak self] diameter in
            guard let self else { return }
            self.mosaicBrushDiameter = diameter
            MosaicBrushCursor.update(diameter: diameter)
        }
        MosaicBrushCursor.update(diameter: mosaicBrushDiameter)
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
        if mosaicArmed {
            if selection.contains(hoverPoint) {
                MosaicBrushCursor.set()
            } else {
                NSCursor.arrow.set()
            }
        } else if committed, !isCustomDragging {
            window?.invalidateCursorRects(for: self)
        }
        needsDisplay = true
    }

    override func resetCursorRects() {
        if mosaicArmed { return }
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
                lastMosaicPoint = nil
                paintMosaicStroke(to: point)
                mosaicPainting = true
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
        if mosaicPainting, mosaicArmed {
            paintMosaicStroke(to: point)
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

    override func mouseUp(with event: NSEvent) {
        guard acceptsPointerInput else { return }
        let point = convert(event.locationInWindow, from: nil)
        if mosaicPainting {
            mosaicPainting = false
            lastMosaicPoint = nil
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
            if committed {
                drawWorkingImage(in: selection)
            }
            let borderRect = selection.insetBy(dx: 0.5, dy: 0.5)
            SelectionChrome.strokeAlternatingBorder(in: borderRect, lineWidth: committed ? 1 : 2)
            if committed {
                let edges: [ResizeEdge] = [.n, .s, .e, .w, .ne, .nw, .se, .sw]
                SelectionChrome.fillHandles(edges.map { handleRect($0) })
            }
            drawSizeBadge()
        }
    }

    override func layout() {
        super.layout()
        layoutChrome()
    }

    private func paintMosaicStroke(to point: CGPoint) {
        guard mosaicArmed, selection.contains(point) else { return }
        if let last = lastMosaicPoint {
            let distance = hypot(point.x - last.x, point.y - last.y)
            let step = max(mosaicBrushDiameter / 4, 2)
            if distance > step {
                let steps = Int(ceil(distance / step))
                for index in 1...steps {
                    let t = CGFloat(index) / CGFloat(steps)
                    let interpolated = CGPoint(
                        x: last.x + (point.x - last.x) * t,
                        y: last.y + (point.y - last.y) * t
                    )
                    stampMosaic(at: interpolated)
                }
            } else if distance > 0.5 {
                stampMosaic(at: point)
            }
        } else {
            stampMosaic(at: point)
        }
        lastMosaicPoint = point
    }

    private func stampMosaic(at viewPoint: CGPoint) {
        guard selection.contains(viewPoint) else { return }
        let imageSize = CGSize(width: workingImage.width, height: workingImage.height)
        let brushRect = CGRect(
            x: viewPoint.x - mosaicBrushDiameter / 2,
            y: viewPoint.y - mosaicBrushDiameter / 2,
            width: mosaicBrushDiameter,
            height: mosaicBrushDiameter
        )
        let pixelRect: CGRect
        if let windowCaptureRect {
            pixelRect = CropGeometry.cropRectWithinWindow(
                selection: brushRect,
                windowRect: windowCaptureRect,
                screenSize: bounds.size,
                imageSize: imageSize
            )
        } else {
            pixelRect = CropGeometry.cropRect(
                localRect: brushRect,
                screenSize: bounds.size,
                imageSize: imageSize
            )
        }
        guard pixelRect.width >= 2, pixelRect.height >= 2 else { return }
        let pixelCenter = CGPoint(x: pixelRect.midX, y: pixelRect.midY)
        let pixelDiameter = max(pixelRect.width, pixelRect.height)
        workingImage = ScreenshotMosaic.applyBrush(
            to: workingImage,
            pixelCenter: pixelCenter,
            pixelDiameter: pixelDiameter
        )
        needsDisplay = true
    }

    private func drawWorkingImage(in localRect: CGRect) {
        let drawRect = localRect.intersection(selection)
        guard !drawRect.isEmpty else { return }
        let imageSize = CGSize(width: workingImage.width, height: workingImage.height)
        let pixelRect: CGRect
        if let windowCaptureRect {
            pixelRect = CropGeometry.cropRectWithinWindow(
                selection: drawRect,
                windowRect: windowCaptureRect,
                screenSize: bounds.size,
                imageSize: imageSize
            )
        } else {
            pixelRect = CropGeometry.cropRect(
                localRect: drawRect,
                screenSize: bounds.size,
                imageSize: imageSize
            )
        }
        guard let piece = workingImage.cropping(to: pixelRect.integral) else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(piece, in: drawRect)
        context.restoreGState()
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
        selection = bounds
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
            toolbar.setMosaicArmed(mosaicArmed, brushDiameter: mosaicBrushDiameter)
            if mosaicArmed {
                MosaicBrushCursor.update(diameter: mosaicBrushDiameter)
                if selection.contains(hoverPoint) {
                    MosaicBrushCursor.set()
                }
            } else {
                mosaicPainting = false
                lastMosaicPoint = nil
                window?.invalidateCursorRects(for: self)
            }
            layoutChrome()
        case .pin:
            onAction?(.pin)
        case .ocr:
            onAction?(.ocr)
        case .translate:
            onAction?(.translate)
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

private enum MosaicBrushCursor {
    private static var cachedDiameter: CGFloat = 24
    private static var cursor: NSCursor?

    static func update(diameter: CGFloat) {
        cachedDiameter = diameter
        cursor = makeCursor(diameter: diameter)
    }

    static func set() {
        (cursor ?? makeCursor(diameter: cachedDiameter)).set()
    }

    private static func makeCursor(diameter: CGFloat) -> NSCursor {
        let padding: CGFloat = 4
        let size = CGSize(width: diameter + padding * 2, height: diameter + padding * 2)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = CGRect(
                x: padding,
                y: padding,
                width: diameter,
                height: diameter
            )
            let path = NSBezierPath(ovalIn: circle)
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1.5
            path.stroke()
            NSColor.black.withAlphaComponent(0.45).setStroke()
            path.lineWidth = 1
            path.setLineDash([2, 2], count: 2, phase: 0)
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
    }
}

private final class ScreenshotMosaicSizePanel: NSView {
    var onChange: ((CGFloat) -> Void)?

    private let slider = NSSlider(value: 24, minValue: 8, maxValue: 64, target: nil, action: nil)
    private let label = NSTextField(labelWithString: UIStrings.Screenshot.mosaicBrushSize)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor(white: 0.14, alpha: 0.96).cgColor

        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor(white: 0.82, alpha: 1)

        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true

        addSubview(label)
        addSubview(slider)
    }

    required init?(coder: NSCoder) { nil }

    var brushDiameter: CGFloat {
        CGFloat(slider.doubleValue)
    }

    func setBrushDiameter(_ diameter: CGFloat) {
        slider.doubleValue = Double(diameter)
    }

    func applyTheme(_ tokens: DesignTokens) {
        layer?.backgroundColor = tokens.nav.nsColor.withAlphaComponent(0.96).cgColor
        label.textColor = tokens.inkSoft.nsColor
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 8
        label.frame = CGRect(x: inset, y: bounds.height - 18, width: bounds.width - inset * 2, height: 14)
        slider.frame = CGRect(x: inset, y: inset, width: bounds.width - inset * 2, height: 16)
    }

    @objc private func sliderChanged() {
        onChange?(brushDiameter)
    }
}

private enum ScreenshotToolbarIcons {
    static func textBadge(_ text: String, tint: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: text == "OCR" ? 7.5 : 10, weight: .bold),
                .foregroundColor: tint,
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                withAttributes: attributes
            )
            return true
        }
    }

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
        case pin, mosaic, ocr, translate, save, cancel, confirm
    }

    var onPick: ((Item) -> Void)?
    var onMosaicBrushDiameterChange: ((CGFloat) -> Void)?
    private var mosaicButton: ScreenshotToolbarButton?
    private var buttons: [ScreenshotToolbarButton] = []
    private let mosaicSizePanel = ScreenshotMosaicSizePanel()

    private let buttonSide: CGFloat = 32
    private let buttonSpacing: CGFloat = 2
    private let horizontalPadding: CGFloat = 8
    private let mosaicPanelHeight: CGFloat = 44
    private let mosaicPanelWidth: CGFloat = 132

    override var intrinsicContentSize: NSSize { fittingSize }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.94).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        mosaicSizePanel.isHidden = true
        mosaicSizePanel.onChange = { [weak self] diameter in
            self?.onMosaicBrushDiameterChange?(diameter)
        }
        addSubview(mosaicSizePanel)

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let items: [(Item, String?, String)] = [
            (.mosaic, nil, UIStrings.Screenshot.mosaic),
            (.ocr, nil, UIStrings.Screenshot.ocr),
            (.translate, nil, UIStrings.Translate.action),
            (.save, "square.and.arrow.down.fill", UIStrings.Screenshot.save),
            (.pin, "pin", UIStrings.Screenshot.pin),
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
            if item == .translate {
                button.isEnabled = ToolRegistry.shared.load().contains {
                    $0.id == TranslateTool.id
                }
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    override var fittingSize: NSSize {
        let count = CGFloat(Item.allCases.count)
        let width = horizontalPadding * 2 + count * buttonSide + (count - 1) * buttonSpacing
        let height = mosaicSizePanel.isHidden ? 40 : 40 + mosaicPanelHeight + 6
        return NSSize(width: width, height: height)
    }

    override func layout() {
        super.layout()
        let y = mosaicSizePanel.isHidden
            ? (bounds.height - buttonSide) / 2
            : bounds.height - buttonSide - 2
        var x = horizontalPadding
        for button in buttons {
            button.frame = CGRect(x: x, y: y, width: buttonSide, height: buttonSide)
            x += buttonSide + buttonSpacing
        }
        if !mosaicSizePanel.isHidden, let mosaicButton {
            let panelX = mosaicButton.frame.midX - mosaicPanelWidth / 2
            mosaicSizePanel.frame = CGRect(
                x: min(max(4, panelX), bounds.width - mosaicPanelWidth - 4),
                y: 4,
                width: mosaicPanelWidth,
                height: mosaicPanelHeight
            )
        }
    }

    func applyTheme(_ tokens: DesignTokens) {
        layer?.backgroundColor = tokens.card.nsColor.withAlphaComponent(0.94).cgColor
        layer?.borderColor = tokens.border.nsColor.cgColor
        mosaicSizePanel.applyTheme(tokens)
        let hover = tokens.ink.nsColor.withAlphaComponent(0.1)
        let armed = tokens.border.nsColor
        let mosaicImage = ScreenshotToolbarIcons.mosaic(size: 14, tint: tokens.controlTint.nsColor)
        let ocrImage = ScreenshotToolbarIcons.textBadge("OCR", tint: tokens.controlTint.nsColor)
        let translateImage = ScreenshotToolbarIcons.textBadge("译", tint: tokens.controlTint.nsColor)
        for button in buttons {
            if button === mosaicButton {
                button.image = mosaicImage
            }
            if button.tag == Item.ocr.rawValue {
                button.image = ocrImage
            } else if button.tag == Item.translate.rawValue {
                button.image = translateImage
            }
            button.applyChrome(
                tint: tokens.controlTint.nsColor,
                hover: hover,
                armed: armed
            )
        }
    }

    func setMosaicArmed(_ armed: Bool, brushDiameter: CGFloat) {
        mosaicButton?.setArmed(armed)
        mosaicSizePanel.isHidden = !armed
        if armed {
            mosaicSizePanel.setBrushDiameter(brushDiameter)
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
        superview?.needsLayout = true
    }

    func setInteractionEnabled(_ enabled: Bool) {
        buttons.forEach { $0.isEnabled = enabled }
    }

    var mosaicBrushDiameter: CGFloat {
        mosaicSizePanel.brushDiameter
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
