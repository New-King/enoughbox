//
//  ScrollingCaptureSession.swift
//  ScrollSnap
//

import AppKit

@MainActor
protocol ImageStitching: AnyObject {
    func startStitching(with initialImage: NSImage)
    func addImage(_ image: NSImage)
    func stopStitching() async -> NSImage?
}

extension StitchingManager: ImageStitching {}

@MainActor
final class ScrollingCaptureSession {
    typealias Capture = @MainActor () async -> NSImage?

    private enum State: Equatable {
        case capturing
        case finishing
        case cancelled
        case finished
    }

    private let capture: Capture
    private let stitcher: any ImageStitching
    private var state = State.capturing
    private var hasStartedStitching = false
    private var captureTask: Task<Void, Never>?

    init(capture: @escaping Capture, stitcher: any ImageStitching = StitchingManager()) {
        self.capture = capture
        self.stitcher = stitcher
    }

    func start() async -> Bool {
        guard state == .capturing, captureTask == nil else { return false }

        captureTask = makeCaptureTask()
        let initialCapture = captureTask
        await initialCapture?.value

        return hasStartedStitching
    }

    @discardableResult
    func requestFrame() -> Bool {
        guard state == .capturing,
              hasStartedStitching,
              captureTask == nil else { return false }

        captureTask = makeCaptureTask()
        return true
    }

    func finish() async -> NSImage? {
        guard state == .capturing else { return nil }
        state = .finishing

        let pendingCapture = captureTask
        await pendingCapture?.value

        guard state == .finishing else { return nil }
        if let terminalImage = await capture(), state == .finishing {
            accept(terminalImage)
        }

        let image = await stitcher.stopStitching()
        state = .finished
        return image
    }

    func cancel() async {
        guard state == .capturing else { return }
        state = .cancelled

        let pendingCapture = captureTask
        await pendingCapture?.value
        _ = await stitcher.stopStitching()
        captureTask = nil
    }

    private func makeCaptureTask() -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await capture()

            if state == .capturing || state == .finishing, let image {
                accept(image)
            }

            captureTask = nil
        }
    }

    private func accept(_ image: NSImage) {
        if hasStartedStitching {
            stitcher.addImage(image)
        } else {
            stitcher.startStitching(with: image)
            hasStartedStitching = true
        }
    }
}
