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
        let screenshotSessionTask = Task { @MainActor in
            await ScreenshotCaptureSession(rectangle: captureRectangle)
        }
        let scrollingCaptureSession = ScrollingCaptureSession {
            guard let screenshotSession = await screenshotSessionTask.value else { return nil }
            return await screenshotSession.capture()
        }
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
        resultContinuation?.resume(returning: image)
        resultContinuation = nil
    }
}
