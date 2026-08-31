//
//  ScreenshotUtilities.swift
//  ScrollSnap
//

import AppKit
import ScreenCaptureKit

@MainActor
final class ScreenshotCaptureSession {
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration
    private let imageSize: NSSize

    init?(rectangle: NSRect) async {
        guard let activeScreen = screenContainingPoint(rectangle.origin),
              let captureContext = await resolveCaptureContext(for: activeScreen) else {
            print("Error: Unable to determine active screen or display.")
            return nil
        }

        let adjustedRect = adjustRectForScreen(rectangle, for: activeScreen)
        let filter = SCContentFilter(
            display: captureContext.display,
            excludingApplications: captureContext.excludedApplications,
            exceptingWindows: []
        )
        let scaleFactor = CGFloat(filter.pointPixelScale)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = adjustedRect
        configuration.width = Int((adjustedRect.width * scaleFactor).rounded())
        configuration.height = Int((adjustedRect.height * scaleFactor).rounded())
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false

        self.filter = filter
        self.configuration = configuration
        imageSize = adjustedRect.size
    }

    func capture() async -> NSImage? {
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return NSImage(cgImage: image, size: imageSize)
        } catch {
            print("Error capturing screenshot: \(error.localizedDescription)")
            return nil
        }
    }
}

private struct ScreenCaptureContext {
    let display: SCDisplay
    let excludedApplications: [SCRunningApplication]
}

/// Determines which screen contains a given point.
///
/// - Parameter point: The `NSPoint` to check against all available screens.
/// - Returns: The `NSScreen` whose frame contains the point, or `nil` if no screen contains it.
/// - Note: Uses the first matching screen; assumes screens don’t overlap significantly.
private func screenContainingPoint(_ point: NSPoint) -> NSScreen? {
    return NSScreen.screens.first { $0.frame.contains(point) }
}

/// Adjusts a rectangle’s Y-coordinate to match the screen’s coordinate system.
///
/// macOS uses a bottom-left origin, while ScreenCaptureKit expects a top-left origin. This function flips the Y-axis accordingly.
///
/// - Parameters:
///   - rect: The `NSRect` to adjust.
///   - screen: The `NSScreen` providing the coordinate context.
/// - Returns: A new `NSRect` with adjusted coordinates.
/// - Note: Subtracts screen’s minX/minY to align with the screen’s local origin.
private func adjustRectForScreen(_ rect: NSRect, for screen: NSScreen) -> NSRect {
    let screenHeight = screen.frame.height + screen.frame.minY
    return NSRect(
        x: rect.origin.x - screen.frame.minX,
        y: screenHeight - rect.origin.y - rect.height,
        width: rect.width,
        height: rect.height
    )
}

/// Resolves the ScreenCaptureKit display and the current app exclusion list from one content snapshot.
///
/// The filtered retrieval matches Apple's sample usage and avoids re-enumerating shareable content for
/// the same screenshot.
private func resolveCaptureContext(for nsScreen: NSScreen) async -> ScreenCaptureContext? {
    guard let screenID = nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
        print("Error: Unable to retrieve screen ID.")
        return nil
    }

    do {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let display = shareableContent.displays.first(where: { $0.displayID == screenID }) else {
            print("Error: Unable to resolve ScreenCaptureKit display.")
            return nil
        }

        let currentPID = NSRunningApplication.current.processIdentifier

        let excludedApplications = shareableContent.applications.filter { $0.processID == currentPID }
        if excludedApplications.isEmpty {
            print("Current application not found in SCShareableContent.")
        }

        return ScreenCaptureContext(display: display, excludedApplications: excludedApplications)
    } catch {
        print("Error fetching shareable content: \(error)")
        return nil
    }
}
