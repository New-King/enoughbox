import AppKit
import SwiftUI

private final class ClipboardNSPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClipboardPanelController: NSWindowController, NSWindowDelegate {
    private let store: ClipboardStore
    private var hostingController: NSHostingController<ClipboardPanelRootView>!
    private var keyMonitor: Any?
    private var presentationID = UUID()
    private(set) var isVisible = false

    init(store: ClipboardStore) {
        self.store = store
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
        dismissPanel(returningToMainWindow: true)
    }

    private func dismissPanel(returningToMainWindow: Bool) {
        prepareForDismissal()
        window?.makeFirstResponder(nil)
        window?.orderOut(nil)
        if returningToMainWindow {
            HostWindowFocus.returnToMainWindow()
        }
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
        applyAndPaste(entry)
    }

    private func pasteFromKeyboard(_ entry: ClipboardItem) {
        applyAndPaste(entry)
    }

    private func applyAndPaste(_ entry: ClipboardItem) {
        let keepOpen = store.isPinned
        guard store.applyToPasteboard(entry) else {
            if !keepOpen {
                dismissPanel(returningToMainWindow: false)
            }
            return
        }
        switch ClipboardPaste.perform(releasing: window, completion: keepOpen ? nil : { [weak self] in
            self?.dismissPanel(returningToMainWindow: false)
        }) {
        case .pasted:
            break
        case .copiedOnly:
            CenterToast.show(UIStrings.Clipboard.toastCopied)
            if !keepOpen {
                dismissPanel(returningToMainWindow: false)
            }
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
            onCopy: { [weak self] entry in
                guard let self, self.store.applyToPasteboard(entry) else { return }
                CenterToast.show(UIStrings.Clipboard.toastCopied)
            },
            onClose: { [weak self] in
                self?.close()
            },
            onClearAll: { [weak self] in
                self?.store.clearAll()
            }
        )
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            switch event.keyCode {
            case 123:
                if self.isEditingSearch() {
                    if self.isComposingSearchText() { return event }
                    return event
                }
                self.store.moveCategory(by: -1)
                return nil
            case 124:
                if self.isEditingSearch() {
                    if self.isComposingSearchText() { return event }
                    return event
                }
                self.store.moveCategory(by: 1)
                return nil
            case 126:
                if self.isEditingSearch() {
                    if self.isComposingSearchText() { return event }
                    return event
                }
                if self.store.selectedIndex <= 0 {
                    self.store.selectedIndex = -1
                    self.store.requestSearchFocus()
                    return nil
                }
                self.store.moveSelection(by: -1)
                return nil
            case 125:
                if self.isEditingSearch() {
                    if self.isComposingSearchText() { return event }
                    self.moveFromSearchToList()
                    return nil
                }
                self.store.moveSelection(by: 1)
                return nil
            case 36, 76:
                if self.isEditingSearch() {
                    if self.isComposingSearchText() { return event }
                    self.moveFromSearchToList()
                    return nil
                }
                if let entry = self.store.selectedEntry {
                    self.pasteFromKeyboard(entry)
                }
                return nil
            case 51:
                if self.isEditingSearch() { return event }
                self.store.removeSelected()
                return nil
            case 53:
                if self.isEditingSearch() {
                    if self.isComposingSearchText() { return event }
                    if !self.store.query.isEmpty {
                        self.store.updateQuery("")
                        return nil
                    }
                }
                self.close()
                return nil
            default:
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if modifiers.isEmpty,
                   event.charactersIgnoringModifiers == "/",
                   !self.isEditingSearch() {
                    self.store.requestSearchFocus()
                    return nil
                }
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

    private func isEditingSearch() -> Bool {
        guard let responder = window?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private func isComposingSearchText() -> Bool {
        guard isEditingSearch() else { return false }
        guard let responder = window?.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            return textView.hasMarkedText()
        }
        if let textField = responder as? NSTextField,
           let editor = textField.currentEditor() as? NSTextView {
            return editor.hasMarkedText()
        }
        return false
    }

    private func moveFromSearchToList() {
        window?.makeFirstResponder(nil)
        store.focusListFromSearch()
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
    let onCopy: (ClipboardItem) -> Void
    let onClose: () -> Void
    let onClearAll: () -> Void

    var body: some View {
        ClipboardPanelView(
            store: store,
            onApply: onApply,
            onDelete: onDelete,
            onCopy: onCopy,
            onClose: onClose,
            onClearAll: onClearAll
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
    let onCopy: (ClipboardItem) -> Void
    let onClose: () -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            header
            searchField
            categoryBar
            entryList
            shortcutFooter
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
        .onChange(of: store.searchFocusToken) { _, _ in
            searchFocused = true
        }
        .onChange(of: store.listFocusToken) { _, _ in
            searchFocused = false
        }
    }

    private var header: some View {
        HStack {
            Button {
                store.isPinned.toggle()
            } label: {
                Image(systemName: store.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.isPinned ? tokens.ink : tokens.inkMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clipboardHoverFill(cornerRadius: 7)
            .help(store.isPinned ? UIStrings.Clipboard.unpin : UIStrings.Clipboard.pin)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.inkMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clipboardHoverFill(cornerRadius: 7)
            .help(UIStrings.Clipboard.close)
        }
        .background(ClipboardWindowDragRegion())
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.inkMuted)
            ZStack(alignment: .leading) {
                if store.query.isEmpty {
                    Text(UIStrings.Clipboard.searchPlaceholder)
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.inkFaint)
                        .allowsHitTesting(false)
                }
                TextField(
                    "",
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
            HStack(spacing: 6) {
                ForEach(ClipboardCategory.allCases) { item in
                    ClipboardCategoryChip(
                        title: categoryTitle(item),
                        isSelected: store.category == item
                    ) {
                        store.updateCategory(item)
                    }
                }
            }

            Spacer(minLength: 8)

            Button(action: onClearAll) {
                Text(UIStrings.Clipboard.clearAll)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(store.entries.isEmpty ? tokens.inkFaint : tokens.inkMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .clipboardHoverFill(cornerRadius: 8)
            .disabled(store.entries.isEmpty)
        }
    }

    private var shortcutFooter: some View {
        HStack(spacing: 0) {
            footerHint(UIStrings.Clipboard.shortcutPaste)
            footerSeparator
            footerHint(UIStrings.Clipboard.shortcutMove)
            footerSeparator
            footerHint(UIStrings.Clipboard.shortcutCategory)
            footerSeparator
            footerHint(UIStrings.Clipboard.shortcutSearch)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private var footerSeparator: some View {
        Text("｜")
            .font(.system(size: 11))
            .foregroundStyle(tokens.inkFaint.opacity(0.4))
    }

    private func footerHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(tokens.inkFaint)
            .lineLimit(1)
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
                                    isSelected: store.selectedIndex >= 0 && index == store.selectedIndex,
                                    onPaste: {
                                        store.selectedIndex = index
                                        onApply(entry)
                                    },
                                    onCopy: { onCopy(entry) },
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
    let onCopy: () -> Void
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

            rowActionButton("square.on.square", help: UIStrings.Clipboard.copy, action: onCopy)
            rowActionButton("trash", help: UIStrings.Clipboard.delete, action: onDelete)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
    }

    private func rowActionButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tokens.inkMuted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .clipboardHoverFill(cornerRadius: 7)
    }

    private var rowBackground: Color {
        if isHovered {
            return tokens.ink.opacity(0.08)
        }
        if isSelected {
            return tokens.accentSoft
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

private struct ClipboardCategoryChip: View {
    @Environment(\.designTokens) private var tokens
    @State private var hovering = false
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? tokens.ink : tokens.inkMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(chipFill, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(tokens.border, lineWidth: isSelected ? 1 : 0)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { hovering = $0 }
    }

    private var chipFill: Color {
        if hovering {
            return tokens.ink.opacity(0.1)
        }
        return isSelected ? tokens.card : tokens.accentSoft
    }
}

private struct ClipboardHoverFill: ViewModifier {
    @Environment(\.designTokens) private var tokens
    var cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(hovering ? tokens.ink.opacity(0.1) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering = $0 }
    }
}

private extension View {
    func clipboardHoverFill(cornerRadius: CGFloat) -> some View {
        modifier(ClipboardHoverFill(cornerRadius: cornerRadius))
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
