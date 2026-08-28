import AppKit

@MainActor
final class ScreenshotOCRResultPanelController {
    private let panel: NSPanel
    private let textView = NSTextView()
    private let copyButton = NSButton()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = UIStrings.Screenshot.ocrResultTitle
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 360, height: 220)
        buildContent()
    }

    func present(text: String) {
        textView.string = text
        panel.setFrameAutosaveName("ScreenshotOCRResult")
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    private func buildContent() {
        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.allowsUndo = true
        scrollView.documentView = textView

        copyButton.title = UIStrings.Screenshot.ocrCopy
        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copyText)

        let closeButton = NSButton()
        closeButton.title = UIStrings.Screenshot.ocrClose
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(close)

        content.addSubview(scrollView)
        content.addSubview(copyButton)
        content.addSubview(closeButton)
        panel.contentView = content

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -12),
            copyButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            copyButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            closeButton.leadingAnchor.constraint(greaterThanOrEqualTo: copyButton.trailingAnchor, constant: 8),
            closeButton.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),
        ])
    }

    @objc private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
    }

    @objc private func close() {
        panel.orderOut(nil)
    }
}
