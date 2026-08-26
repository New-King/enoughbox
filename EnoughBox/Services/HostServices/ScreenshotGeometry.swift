import AppKit
import CoreGraphics

/// Coordinate helpers and window picking for the screenshot overlay.
enum ScreenshotGeometry {
    static let clickDragThreshold: CGFloat = 4

    struct PickableWindow: Equatable {
        let windowID: CGWindowID
        /// Frame in the overlay view's bottom-left coordinate system.
        let frame: CGRect
    }

    static func isClick(from origin: CGPoint, to end: CGPoint) -> Bool {
        abs(end.x - origin.x) < clickDragThreshold && abs(end.y - origin.y) < clickDragThreshold
    }

    static func selectionAcceptsPointerInput(capturePending: Bool) -> Bool {
        !capturePending
    }

    /// On-screen layer-zero windows in window-server order (front to back).
    static func pickableWindows(
        on screen: NSScreen,
        protectedWindowIDs: Set<CGWindowID>
    ) -> [PickableWindow] {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenFrame = screen.frame

        return info.compactMap { entry in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }

            let isOwn = pid == ownPID
            guard ScreenshotCapturePolicy.canPickWindow(
                id,
                isOwnWindow: isOwn,
                protectedWindowIDs: protectedWindowIDs
            ) else { return nil }

            let serverRect = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            guard serverRect.width >= 40, serverRect.height >= 40 else { return nil }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { return nil }

            let viewRect = viewRect(
                fromWindowServer: serverRect,
                screenFrame: screenFrame,
                mainScreenHeight: mainHeight
            ).intersection(CGRect(origin: .zero, size: screenFrame.size))
            guard viewRect.width >= 8, viewRect.height >= 8 else { return nil }
            return PickableWindow(windowID: id, frame: viewRect)
        }
    }

    static func window(at point: CGPoint, in windows: [PickableWindow]) -> PickableWindow? {
        windows.first { $0.frame.contains(point) }
    }

    static func cocoaRect(fromWindowServer rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: mainScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func viewRect(
        fromWindowServer rect: CGRect,
        screenFrame: CGRect,
        mainScreenHeight: CGFloat
    ) -> CGRect {
        let cocoa = cocoaRect(fromWindowServer: rect, mainScreenHeight: mainScreenHeight)
        return CGRect(
            x: cocoa.origin.x - screenFrame.origin.x,
            y: cocoa.origin.y - screenFrame.origin.y,
            width: cocoa.width,
            height: cocoa.height
        )
    }

    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var result = rect.intersection(bounds)
        if result.isNull { result = .zero }
        return result
    }
}
