import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureError: Error {
    case displayUnavailable
    case imageUnavailable
    case permissionDenied
}

struct FrozenDisplay {
    let screen: NSScreen
    let image: CGImage
}

/// ScreenCaptureKit stills. Overlay panels are created *after* this freeze and
/// use `sharingType = .none`, so they are not in the bitmap.
enum ScreenCapture {
    static func hasAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system screen-recording permission sheet (same as accessibility trust prompt).
    static func requestScreenCaptureTrust() {
        if CGPreflightScreenCaptureAccess() { return }
        _ = CGRequestScreenCaptureAccess()
    }

    static func requestAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    static func freezeDisplays(protectedWindowIDs: Set<CGWindowID>) async throws -> [FrozenDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownWindowIDs = Set(content.windows.compactMap { window in
            window.owningApplication?.processID == getpid() ? window.windowID : nil
        })
        let excludedIDs = ScreenshotCapturePolicy.excludedOwnWindowIDs(
            ownWindowIDs: ownWindowIDs,
            protectedWindowIDs: protectedWindowIDs
        )
        let excludedWindows = content.windows.filter { excludedIDs.contains($0.windowID) }

        var frames: [FrozenDisplay] = []
        for screen in NSScreen.screens {
            guard let display = display(for: screen, in: content) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let configuration = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            configuration.width = max(1, Int(screen.frame.width * scale))
            configuration.height = max(1, Int(screen.frame.height * scale))
            configuration.showsCursor = false
            configuration.colorSpaceName = CGColorSpace.sRGB
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            frames.append(FrozenDisplay(screen: screen, image: image))
        }
        if frames.isEmpty { throw ScreenCaptureError.displayUnavailable }
        return frames
    }

    /// Window buffer via ScreenCaptureKit (crisp edges, no neighbor bleed).
    static func captureWindow(_ windowID: CGWindowID, scale: CGFloat) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == windowID })
        else { return nil }

        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((window.frame.width * scale).rounded()))
        configuration.height = max(1, Int((window.frame.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    static func crop(_ image: CGImage, localRect: CGRect, screenSize: CGSize) throws -> CGImage {
        let rect = CropGeometry.cropRect(
            localRect: localRect,
            screenSize: screenSize,
            imageSize: CGSize(width: image.width, height: image.height)
        )
        guard !rect.isEmpty, let cropped = image.cropping(to: rect) else {
            throw ScreenCaptureError.imageUnavailable
        }
        return cropped
    }

    static func cropWithinWindow(
        _ image: CGImage,
        selection: CGRect,
        windowRect: CGRect,
        screenSize: CGSize
    ) throws -> CGImage {
        let rect = CropGeometry.cropRectWithinWindow(
            selection: selection,
            windowRect: windowRect,
            screenSize: screenSize,
            imageSize: CGSize(width: image.width, height: image.height)
        )
        guard !rect.isEmpty, let cropped = image.cropping(to: rect) else {
            throw ScreenCaptureError.imageUnavailable
        }
        return cropped
    }

    private static func display(for screen: NSScreen, in content: SCShareableContent) -> SCDisplay? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        return content.displays.first { $0.displayID == displayID }
    }
}
