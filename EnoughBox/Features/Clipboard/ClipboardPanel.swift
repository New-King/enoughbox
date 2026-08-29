import AppKit
import SwiftUI

private final class ClipboardNSPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClipboardPanelController: NSWindowController, NSWindowDelegate {
    private let store: ClipboardStore
    private let toastHandler: (String) -> Void
    private var hostingController: NSHostingController<ClipboardPanelRootView>!
    private var keyMonitor: Any?
    private var presentationID = UUID()
    private(set) var isVisible = false

    init(
        store: ClipboardStore,
        toastHandler: @escaping (String) -> Void
    ) {
        self.store = store
        self.toastHandler = toastHandler
        let panel = ClipboardNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 440),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        hostingController = makeHostingController()
        panel.contentViewController = hostingController
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        ClipboardPaste.rememberTarget()
        presentationID = UUID()
        hostingController.rootView = makeRootView()
        store.resetPanelState()
        guard let window else { return }
        positionNearMouse(window)
        window.orderFrontRegardless()
        window.makeKey()
        isVisible = true
        installKeyMonitor()
    }

    override func close() {
        prepareForDismissal()
        window?.makeFirstResponder(nil)
        window?.orderOut(nil)
        HostWindowFocus.returnToMainWindow()
    }

    func windowWillClose(_ notification: Notification) {
        prepareForDismissal()
        HostWindowFocus.returnToMainWindow()
    }

    private func prepareForDismissal() {
        guard isVisible else { return }
        removeKeyMonitor()
        store.endPanelSession()
        isVisible = false
    }

    private func paste(_ entry: ClipboardItem) {
        guard store.applyToPasteboard(entry) else { return }
        switch ClipboardPaste.perform(releasing: window) {
        case .pasted:
            break
        case .copiedOnly:
            toastHandler(UIStrings.Clipboard.toastCopied)
        }
    }

    private func makeHostingController() -> NSHostingController<ClipboardPanelRootView> {
        NSHostingController(rootView: makeRootView())
    }

    private func makeRootView() -> ClipboardPanelRootView {
        ClipboardPanelRootView(
            presentationID: presentationID,
            store: store,
            onApply: { [weak self] entry in
                self?.paste(entry)
            },
            onDelete: { [weak self] entry in
                self?.store.remove(entry)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            switch event.keyCode {
            case 53:
                self.close()
                return nil
            case 126:
                self.store.moveSelection(by: -1)
                return nil
            case 125:
                self.store.moveSelection(by: 1)
                return nil
            case 36, 76:
                if let entry = self.store.selectedEntry {
                    self.paste(entry)
                }
                return nil
            case 51:
                self.store.removeSelected()
                return nil
            default:
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if modifiers == .command,
                   let key = event.charactersIgnoringModifiers?.lowercased(),
                   key == "w" || key == "q" {
                    self.close()
                    return nil
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func positionNearMouse(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - window.frame.height - 12)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - window.frame.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - window.frame.height - 8)
        }
        window.setFrameOrigin(origin)
    }
}

private struct ClipboardPanelRootView: View {
    let presentationID: UUID
    @ObservedObject var store: ClipboardStore
    let onApply: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void
    let onClose: () -> Void

    var body: some View {
        ClipboardPanelView(
            store: store,
            onApply: onApply,
            onDelete: onDelete,
            onClose: onClose
        )
        .preferredColorScheme(AppearanceMode.stored.effectiveColorScheme)
        .designTokensProvider()
        .id(presentationID)
    }
}

private struct ClipboardPanelView: View {
    @ObservedObject var store: ClipboardStore
    @Environment(\.designTokens) private var tokens
    @FocusState private var searchFocused: Bool
    let onApply: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            header
            searchField
            categoryBar
            entryList
        }
        .padding(12)
        .frame(width: 360, height: 440)
        .background(tokens.page)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(tokens.border, lineWidth: 1)
        )
        .appleShadow(tokens)
    }

    private var header: some View {
        HStack {
            Text(UIStrings.Tool.clipboardName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tokens.ink)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.inkMuted)
                    .frame(width: 24, height: 24)
                    .background(tokens.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .background(ClipboardWindowDragRegion())
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.inkMuted)
            TextField(
                UIStrings.Clipboard.searchPlaceholder,
                text: Binding(
                    get: { store.query },
                    set: { store.updateQuery($0) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(tokens.ink)
            .focused($searchFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tokens.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tokens.border, lineWidth: 1)
        )
    }

    private var categoryBar: some View {
        HStack(spacing: 6) {
            ForEach(ClipboardCategory.allCases) { item in
                Button {
                    store.updateCategory(item)
                } label: {
                    Text(categoryTitle(item))
                        .font(.system(size: 11, weight: store.category == item ? .semibold : .medium))
                        .foregroundStyle(store.category == item ? tokens.ink : tokens.inkMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            store.category == item ? tokens.accentSoft : tokens.card,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(tokens.border, lineWidth: store.category == item ? 0 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var entryList: some View {
        Group {
            if store.filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(UIStrings.Clipboard.empty)
                        .font(.system(size: 13))
                        .foregroundStyle(tokens.inkMuted)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(store.filteredEntries.enumerated()), id: \.element.id) { index, entry in
                                ClipboardRowView(
                                    entry: entry,
                                    isSelected: index == store.selectedIndex,
                                    onPaste: {
                                        store.selectedIndex = index
                                        onApply(entry)
                                    },
                                    onDelete: { onDelete(entry) }
                                )
                                .id(entry.id)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: store.selectedIndex) { _, newValue in
                        guard store.filteredEntries.indices.contains(newValue) else { return }
                        let id = store.filteredEntries[newValue].id
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tokens.border, lineWidth: 1)
        )
    }

    private func categoryTitle(_ category: ClipboardCategory) -> String {
        switch category {
        case .recent: UIStrings.Clipboard.categoryRecent
        case .all: UIStrings.Clipboard.categoryAll
        case .text: UIStrings.Clipboard.categoryText
        case .image: UIStrings.Clipboard.categoryImage
        case .other: UIStrings.Clipboard.categoryOther
        }
    }
}

private struct ClipboardRowView: View {
    @Environment(\.designTokens) private var tokens
    let entry: ClipboardItem
    let isSelected: Bool
    let onPaste: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPaste) {
                HStack(spacing: 10) {
                    leadingVisual
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.preview)
                            .font(.system(size: 12))
                            .foregroundStyle(tokens.ink)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Text(entry.copiedAt, style: .time)
                            .font(.system(size: 10))
                            .foregroundStyle(tokens.inkFaint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tokens.inkMuted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(UIStrings.Clipboard.delete)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected {
            return tokens.accentSoft
        }
        if isHovered {
            return tokens.ink.opacity(0.08)
        }
        return .clear
    }

    @ViewBuilder
    private var leadingVisual: some View {
        switch entry.kind {
        case .image:
            ClipboardThumbnailView(imageFile: entry.imageFile, size: 36)
        case .text:
            icon("doc.text")
        case .other:
            icon(entry.filePaths.isEmpty ? "questionmark.square.dashed" : "doc")
        }
    }

    private func icon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tokens.inkMuted)
            .frame(width: 36, height: 36)
            .background(tokens.page, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct ClipboardWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ClipboardWindowDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ClipboardWindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
