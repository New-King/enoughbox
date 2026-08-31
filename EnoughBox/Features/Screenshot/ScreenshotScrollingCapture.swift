import AppKit

/// Capture loop copied from ScrollSnap `OverlayManager` (`captureScreenshot` / `startScrollingCapture` / `stopScrollingCapture` / timer).
@MainActor
final class OverlayCaptureDriver {
    private enum CaptureSessionState {
        case idle
        case selecting
        case capturing
        case finishing
        case thumbnail
    }

    private var rectangle: NSRect = .zero
    private var isScrollingCaptureActive = false
    private var captureSessionID: UUID?
    private var captureTimer: Timer?
    private var scrollingCaptureSession: ScrollingCaptureSession?
    private var sessionState: CaptureSessionState = .idle
    private var resultContinuation: CheckedContinuation<NSImage?, Never>?
    private var previewPump: ScrollingPreviewPump?

    init(onPreview: @escaping (NSImage, Int) -> Void = { _, _ in }) {
        previewPump = ScrollingPreviewPump(onPreview: onPreview)
    }

    func run(rectangle: NSRect) async -> NSImage? {
        self.rectangle = rectangle
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
            captureScreenshot()
        }
    }

    /// Initiates or stops screenshot capture based on current mode.
    func captureScreenshot() {
        switch sessionState {
        case .idle, .selecting:
            let sessionID = UUID()
            captureSessionID = sessionID
            sessionState = .capturing
            Task { [weak self] in
                await self?.startScrollingCapture(sessionID: sessionID)
            }
        case .capturing:
            guard let sessionID = captureSessionID,
                  isScrollingCaptureActive else { return }
            isScrollingCaptureActive = false
            sessionState = .finishing
            Task { [weak self] in
                await self?.stopScrollingCapture(sessionID: sessionID)
            }
        case .finishing, .thumbnail:
            break
        }
    }

    func cancelScrollingCapture() {
        guard sessionState == .capturing,
              captureSessionID != nil else { return }

        let scrollingCaptureSession = scrollingCaptureSession
        self.scrollingCaptureSession = nil
        captureSessionID = nil
        isScrollingCaptureActive = false
        invalidateCaptureTimer()
        previewPump?.cancel()

        Task { [weak self] in
            guard let self else { return }
            await scrollingCaptureSession?.cancel()
            guard self.sessionState == .capturing,
                  self.captureSessionID == nil else { return }
            self.sessionState = .idle
            self.finishWith(nil)
        }
    }

    /// Stops the scrolling capture process and saves collected images.
    private func stopScrollingCapture(sessionID: UUID) async {
        guard captureSessionID == sessionID,
              sessionState == .finishing,
              let scrollingCaptureSession else { return }

        isScrollingCaptureActive = false
        invalidateCaptureTimer()
        previewPump?.cancel()

        guard let finalImage = await scrollingCaptureSession.finish(),
              captureSessionID == sessionID else {
            guard captureSessionID == sessionID else { return }
            self.scrollingCaptureSession = nil
            captureSessionID = nil
            sessionState = .idle
            finishWith(nil)
            return
        }

        self.scrollingCaptureSession = nil
        captureSessionID = nil
        sessionState = .idle
        finishWith(finalImage)
    }

    /// Starts the scrolling capture process.
    private func startScrollingCapture(sessionID: UUID) async {
        guard captureSessionID == sessionID,
              sessionState == .capturing else { return }

        let captureRectangle = rectangle
        let pump = previewPump
        let screenshotSessionTask = Task { @MainActor in
            await ScreenshotCaptureSession(rectangle: captureRectangle)
        }
        let scrollingCaptureSession = ScrollingCaptureSession(
            capture: {
                guard let screenshotSession = await screenshotSessionTask.value else { return nil }
                return await screenshotSession.capture()
            },
            stitcher: StitchingManager(previewHandler: { image in
                pump?.submit(image)
            })
        )
        self.scrollingCaptureSession = scrollingCaptureSession
        isScrollingCaptureActive = true

        let didStart = await scrollingCaptureSession.start()

        guard captureSessionID == sessionID,
              isScrollingCaptureActive,
              sessionState == .capturing else {
            if captureSessionID == sessionID, sessionState == .finishing {
                return
            }
            await scrollingCaptureSession.cancel()
            if self.scrollingCaptureSession === scrollingCaptureSession {
                self.scrollingCaptureSession = nil
            }
            return
        }

        guard didStart else {
            isScrollingCaptureActive = false
            self.scrollingCaptureSession = nil
            captureSessionID = nil
            sessionState = .selecting
            finishWith(nil)
            return
        }

        setupCaptureTimer(sessionID: sessionID)
    }

    private func setupCaptureTimer(sessionID: UUID) {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      self.captureSessionID == sessionID,
                      self.isScrollingCaptureActive,
                      self.sessionState == .capturing else { return }

                self.scrollingCaptureSession?.requestFrame()
            }
        }
        captureTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func invalidateCaptureTimer() {
        captureTimer?.invalidate()
        captureTimer = nil
    }

    private func finishWith(_ image: NSImage?) {
        previewPump?.cancel()
        resultContinuation?.resume(returning: image)
        resultContinuation = nil
    }
}

/// Latest-wins preview on a utility queue. Must not run on the stitching queue or use `lockFocus`.
private final class ScrollingPreviewPump: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.enoughbox.scroll-preview", qos: .utility)
    private let onPreview: (NSImage, Int) -> Void
    private var latest: NSImage?
    private var busy = false
    private var cancelled = false

    init(onPreview: @escaping (NSImage, Int) -> Void) {
        self.onPreview = onPreview
    }

    func submit(_ image: NSImage) {
        queue.async { [weak self] in
            guard let self, !self.cancelled else { return }
            self.latest = image
            self.drain()
        }
    }

    func cancel() {
        queue.async { [weak self] in
            self?.cancelled = true
            self?.latest = nil
        }
    }

    private func drain() {
        guard !cancelled, !busy, let image = latest else { return }
        latest = nil
        busy = true
        let height = Self.pixelHeight(of: image)
        let thumbnail = Self.thumbnail(from: image) ?? image
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.cancelled {
                self.onPreview(thumbnail, height)
            }
            self.queue.async {
                self.busy = false
                self.drain()
            }
        }
    }

    private static func pixelHeight(of image: NSImage) -> Int {
        if let pixelsHigh = image.representations.compactMap({ $0 as? NSBitmapImageRep }).map(\.pixelsHigh).max(),
           pixelsHigh > 0 {
            return pixelsHigh
        }
        return max(1, Int(image.size.height.rounded()))
    }

    private static func thumbnail(from image: NSImage) -> NSImage? {
        guard let cgImage = cgImage(from: image), cgImage.width > 0, cgImage.height > 0 else { return nil }
        let maxWidth = 256
        let scale = min(1, CGFloat(maxWidth) / CGFloat(cgImage.width))
        let width = max(1, Int((CGFloat(cgImage.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(cgImage.height) * scale).rounded()))
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSImage(cgImage: scaled, size: NSSize(width: width, height: height))
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        for representation in image.representations {
            if let bitmap = representation as? NSBitmapImageRep, let cgImage = bitmap.cgImage {
                return cgImage
            }
        }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
