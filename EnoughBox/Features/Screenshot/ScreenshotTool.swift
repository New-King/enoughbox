import AppKit
import SwiftUI

@MainActor
final class ScreenshotTool {
    static let id = "com.enoughbox.screenshot"

    private let toastHandler: (String) -> Void
    private let overlay = ScreenshotOverlayController()

    init(toastHandler: @escaping (String) -> Void) {
        self.toastHandler = toastHandler
        overlay.onCopied = { [weak self] message in
            self?.toastHandler(message)
        }
        overlay.onSaved = { [weak self] name in
            self?.toastHandler(
                String(format: ScreenshotL10n.string("plugin.screenshot.toast.saved"), name)
            )
        }
        overlay.onFailed = { [weak self] in
            self?.toastHandler(ScreenshotL10n.string("plugin.screenshot.toast.failed"))
        }
    }

    func activate() {
        HotkeyCenter.shared.register(HotkeyCatalog.screenshotRegionID) { [weak self] in
            self?.startCapture()
        }
    }

    func deactivate() {
        HotkeyCenter.shared.unregister(HotkeyCatalog.screenshotRegionID)
        overlay.cancel()
    }

    /// Hotkey: authorized → overlay; otherwise system permission sheet only.
    func startCapture() {
        if ScreenCapture.hasAccess() {
            overlay.start()
        } else {
            ScreenCapture.requestScreenCaptureTrust()
        }
    }
}

enum ScreenshotL10n {
    static let bundle = Bundle.main
    static let tableName = "ScreenshotLocalizable"

    static func string(_ key: String) -> String {
        NSLocalizedString(key, tableName: tableName, bundle: bundle, comment: "")
    }
}

struct ScreenshotSettingsView: View {
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("plugin.screenshot.settings.section", tableName: ScreenshotL10n.tableName, bundle: ScreenshotL10n.bundle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.inkMuted)
                .textCase(.uppercase)

            Text("plugin.screenshot.settings.hint", tableName: ScreenshotL10n.tableName, bundle: ScreenshotL10n.bundle)
                .font(.system(size: 13))
                .foregroundStyle(tokens.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Text("plugin.screenshot.settings.colorHint", tableName: ScreenshotL10n.tableName, bundle: ScreenshotL10n.bundle)
                .font(.system(size: 11))
                .foregroundStyle(tokens.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(action: openScreenRecordingPermission) {
                    Text("plugin.screenshot.settings.openPermission", tableName: ScreenshotL10n.tableName, bundle: ScreenshotL10n.bundle)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(tokens.ink)
                        .background(tokens.ink.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tokens.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tokens.border, lineWidth: 1)
        )
    }

    private func openScreenRecordingPermission() {
        if ScreenCapture.hasAccess() {
            ScreenCapture.openScreenRecordingSettings()
        } else {
            ScreenCapture.requestScreenCaptureTrust()
        }
    }
}
