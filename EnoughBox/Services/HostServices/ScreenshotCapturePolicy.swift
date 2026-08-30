import CoreGraphics

/// Which of this process's windows ScreenCaptureKit must exclude from display
/// captures. Only IDs in `protectedWindowIDs` are removed so the main window
/// can stay visible while overlay UI is created after the freeze.
enum ScreenshotCapturePolicy {
    static func excludedOwnWindowIDs(
        hideOwnWindows: Bool,
        ownWindowIDs: Set<CGWindowID>,
        protectedWindowIDs: Set<CGWindowID>
    ) -> Set<CGWindowID> {
        hideOwnWindows ? ownWindowIDs : ownWindowIDs.intersection(protectedWindowIDs)
    }

    static func canPickWindow(
        _ windowID: CGWindowID,
        isOwnWindow: Bool,
        protectedWindowIDs: Set<CGWindowID>
    ) -> Bool {
        !isOwnWindow || !protectedWindowIDs.contains(windowID)
    }
}
