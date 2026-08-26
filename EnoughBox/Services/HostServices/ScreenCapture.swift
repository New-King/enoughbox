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

/// ScreenCaptureKit stills. Overlay UI must set `sharingType = .none` and be
/// created *after* this freeze so it is not in the bitmap.
enum ScreenCapture {
    static func hasAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    static func freezeDisplays() async throws -> [FrozenDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownID = Bundle.main.bundleIdentifier
        var frames: [FrozenDisplay] = []
        for screen in NSScreen.screens {
            guard let display = display(for: screen, in: content) else { continue }
            let excluded = content.applications.filter { $0.bundleIdentifier == ownID }
            let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            configuration.width = max(1, Int(screen.frame.width * scale))
            configuration.height = max(1, Int(screen.frame.height * scale))
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            frames.append(FrozenDisplay(screen: screen, image: image))
        }
        if frames.isEmpty { throw ScreenCaptureError.displayUnavailable }
        return frames
    }

    static func crop(_ image: CGImage, localRect: CGRect, screenSize: CGSize) throws -> CGImage {
        let rect = CropGeometry.cropRect(localRect: localRect, screenSize: screenSize, imageSize: CGSize(width: image.width, height: image.height))
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
