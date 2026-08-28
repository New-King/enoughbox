import AppKit
import AVFoundation
import Combine
import SwiftUI
#if canImport(Translation)
import Translation
#endif

@MainActor
final class TranslationPanelModel: ObservableObject {
    @Published var sourceRevision = UUID()
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var isPinned = false
    @Published var isTranslating = false
    @Published var targetLanguage = TranslateSettings.targetLanguage
    @Published var detectedLanguage: TranslateLanguage = .en
    @Published var engine = TranslateSettings.engine
    @Published var appleRequestID: UUID?

    private var translateTask: Task<Void, Never>?
    private var requestID = UUID()
    private let synthesizer = AVSpeechSynthesizer()

    func present(sourceText: String) {
        sourceRevision = UUID()
        self.sourceText = sourceText
        targetLanguage = TranslateSettings.targetLanguage
        engine = TranslateSettings.engine
        detectedLanguage = LanguageDetector.detect(sourceText)
        if sourceText.isEmpty {
            translatedText = ""
            isTranslating = false
            return
        }
        translate()
    }

    var visibleTargetLanguage: TranslateLanguage {
        targetLanguage.resolvedTarget(for: detectedLanguage)
    }

    /// Cycles the session engine without writing `TranslateSettings.engine`.
    func cycleEngine() {
        engine = engine.next()
        translate()
    }

    func translate() {
        TranslateSettings.targetLanguage = targetLanguage
        detectedLanguage = LanguageDetector.detect(sourceText)
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = targetLanguage.resolvedTarget(for: detectedLanguage)
        let source = detectedLanguage
        translateTask?.cancel()
        let id = UUID()
        requestID = id
        appleRequestID = nil
        guard !text.isEmpty else {
            translatedText = ""
            isTranslating = false
            return
        }
        isTranslating = true
        if engine == .system {
            #if canImport(Translation)
            if #available(macOS 15.0, *) {
                appleRequestID = id
                return
            }
            #endif
            translatedText = TranslatorError.systemUnavailable.localizedDescription
            isTranslating = false
            return
        }

        translateTask = Task {
            do {
                let translator = try TranslateSettings.translator(for: engine)
                let result = try await translator.translate(text, from: source, to: target)
                guard !Task.isCancelled, requestID == id else { return }
                translatedText = result
            } catch is CancellationError {
                return
            } catch {
                guard requestID == id else { return }
                translatedText = error.localizedDescription
            }
            isTranslating = false
        }
    }

    func completeAppleTranslation(requestID: UUID, text: String) {
        guard self.requestID == requestID else { return }
        translatedText = text
        isTranslating = false
        appleRequestID = nil
    }

    func failAppleTranslation(requestID: UUID, message: String) {
        guard self.requestID == requestID else { return }
        translatedText = message
        isTranslating = false
        appleRequestID = nil
    }

    func toggleTargetLanguage() {
        switch targetLanguage {
        case .auto:
            targetLanguage = detectedLanguage == .zhHans ? .en : .zhHans
        case .en:
            targetLanguage = .zhHans
        case .zhHans:
            targetLanguage = .auto
        }
        TranslateSettings.targetLanguage = targetLanguage
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        translate()
    }

    func clearSource() {
        translateTask?.cancel()
        translateTask = nil
        sourceText = ""
        translatedText = ""
        isTranslating = false
    }

    func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func speak(_ text: String, language: TranslateLanguage) {
        guard !text.isEmpty else { return }
        let speechLanguage = language.resolvedTarget(for: detectedLanguage)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: speechLanguage.speechLanguage)
        synthesizer.speak(utterance)
    }
}

/// Borderless `NSPanel` cannot become key unless this is overridden, so TextEditor never focuses.
private final class TranslationNSPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TranslationPanelController: NSWindowController, NSWindowDelegate {
    private let session = TranslationPanelModel()
    private var hostingController: NSHostingController<TranslationPanelRootView>!
    private var lastFittedSize: CGSize = .zero
    private var clickOutsideMonitor: Any?

    convenience init() {
        let panel = TranslationNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
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

        self.init(window: panel)
        let hosting = NSHostingController(
            rootView: TranslationPanelRootView(
                session: session,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )
        hostingController = hosting
        panel.contentViewController = hosting
        panel.delegate = self
        session.$isPinned
            .receive(on: RunLoop.main)
            .sink { [weak panel] pinned in
                panel?.level = pinned ? .statusBar : .floating
            }
            .store(in: &cancellables)
        Publishers.CombineLatest(session.$translatedText, session.$isTranslating)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.scheduleFit()
            }
            .store(in: &cancellables)
        installCloseKeyMonitor()
    }

    private var cancellables = Set<AnyCancellable>()
    private var keyMonitor: Any?

    func present(sourceText: String) {
        lastFittedSize = .zero
        session.isPinned = false
        session.present(sourceText: sourceText)
        guard let window else { return }
        positionNearMouse(window)
        window.orderFrontRegardless()
        window.makeKey()
        installClickOutsideMonitor()
        scheduleFit()
    }

    override func close() {
        removeClickOutsideMonitor()
        window?.makeFirstResponder(nil)
        window?.orderOut(nil)
        HostWindowFocus.returnToMainWindow()
    }

    func windowDidResignKey(_ notification: Notification) {
        dismissIfClickOutside()
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.dismissIfClickOutside()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
    }

    private func dismissIfClickOutside() {
        guard let window, window.isVisible, !session.isPinned else { return }
        let click = NSEvent.mouseLocation
        if !window.frame.contains(click) {
            close()
        }
    }

    private func installCloseKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == 53 {
                self.close()
                return nil
            }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == .command,
               let key = event.charactersIgnoringModifiers?.lowercased(),
               key == "w" || key == "q"
            {
                self.close()
                return nil
            }
            return event
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

    private func scheduleFit() {
        DispatchQueue.main.async { [weak self] in
            self?.fitToFittingSize()
            DispatchQueue.main.async {
                self?.fitToFittingSize()
            }
        }
    }

    /// Resize only after translation content changes — not on every layout pass
    /// (that loop stole TextEditor focus and flickered the cursor).
    private func fitToFittingSize() {
        guard let window, let hostingController else { return }
        let fitted = hostingController.sizeThatFits(in: CGSize(width: 380, height: 10_000))
        let height = ceil(fitted.height)
        guard height > 40 else { return }
        let next = CGSize(width: 380, height: height)
        guard abs(next.width - lastFittedSize.width) > 0.5 || abs(next.height - lastFittedSize.height) > 0.5 else {
            return
        }
        lastFittedSize = next
        var frame = window.frame
        let top = frame.maxY
        frame.size = next
        frame.origin.y = top - next.height
        if let screen = window.screen ?? NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
            if frame.minX < visible.minX { frame.origin.x = visible.minX }
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
            if frame.minY < visible.minY { frame.origin.y = visible.minY }
        }
        window.setFrame(frame, display: true)
    }
}

private struct TranslationPanelRootView: View {
    @ObservedObject var session: TranslationPanelModel
    let onClose: () -> Void

    var body: some View {
        TranslationPanelView(session: session, onClose: onClose)
            .preferredColorScheme(AppearanceMode.stored.effectiveColorScheme)
            .designTokensProvider()
    }
}

private struct TranslationPanelView: View {
    @ObservedObject var session: TranslationPanelModel
    @Environment(\.designTokens) private var tokens
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            header
            sourceCard
            languageBar
            resultCard
        }
        .padding(12)
        .frame(width: 380)
        .background(tokens.page)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(tokens.border, lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
        .modifier(AppleTranslationBridge(session: session))
    }

    private var header: some View {
        HStack {
            panelIconButton(session.isPinned ? "pin.fill" : "pin") {
                session.isPinned.toggle()
            }
            Spacer()
            panelIconButton("xmark") {
                onClose()
            }
        }
        .background(WindowDragRegion())
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $session.sourceText)
                .id(session.sourceRevision)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 72, maxHeight: 110)
                .foregroundStyle(tokens.ink)

            HStack(spacing: 8) {
                panelIconButton("speaker.wave.2") {
                    session.speak(session.sourceText, language: session.detectedLanguage)
                }
                panelIconButton("square.on.square") {
                    session.copy(session.sourceText)
                }
                panelIconButton("xmark.square") {
                    session.clearSource()
                }

                languageChip(session.detectedLanguage.localizedName)

                Spacer(minLength: 8)

                Button(action: session.translate) {
                    HStack(spacing: 4) {
                        Image(systemName: "character.book.closed")
                        Text(UIStrings.Translate.action)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(tokens.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(session.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(tokens.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var languageBar: some View {
        HStack {
            Text(session.sourceText.isEmpty
                 ? UIStrings.Translate.sourceAuto
                 : session.detectedLanguage.localizedName)
                .font(.system(size: 12))
                .foregroundStyle(tokens.inkSoft)
            Spacer()
            Button(action: session.toggleTargetLanguage) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tokens.inkMuted)
            }
            .buttonStyle(.plain)
            .help(UIStrings.Translate.swap)
            Spacer()
            Picker("", selection: Binding(
                get: { session.visibleTargetLanguage },
                set: { newValue in
                    session.targetLanguage = newValue
                    session.translate()
                }
            )) {
                ForEach([TranslateLanguage.zhHans, .en]) { language in
                    Text(language.localizedName).tag(language)
                }
            }
            .labelsHidden()
            .frame(width: 110)
        }
        .padding(.horizontal, 4)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.ink)
                Text(session.engine.localizedName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.ink)
                Button(action: session.cycleEngine) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tokens.inkMuted)
                }
                .buttonStyle(TranslationPanelIconButtonStyle(hoverFill: tokens.ink.opacity(0.1)))
                .help(UIStrings.Translate.cycleEngine)
                .accessibilityLabel(UIStrings.Translate.cycleEngine)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(tokens.accentSoft)

            Group {
                if session.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
                } else {
                    GrowingResultText(
                        text: session.translatedText.isEmpty
                            ? UIStrings.Translate.resultEmpty
                            : session.translatedText,
                        isPlaceholder: session.translatedText.isEmpty,
                        ink: tokens.ink,
                        inkFaint: tokens.inkFaint
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            HStack(spacing: 8) {
                panelIconButton("speaker.wave.2") {
                    session.speak(session.translatedText, language: session.targetLanguage)
                }
                panelIconButton("square.on.square") {
                    session.copy(session.translatedText)
                }
                panelIconButton("arrow.clockwise") {
                    session.translate()
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.card)
            .layoutPriority(1)
        }
        .background(tokens.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(tokens.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func languageChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tokens.inkSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tokens.card, in: Capsule())
            .overlay(Capsule().strokeBorder(tokens.border, lineWidth: 1))
    }

    private func panelIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.inkMuted)
        }
        .buttonStyle(TranslationPanelIconButtonStyle(hoverFill: tokens.ink.opacity(0.1)))
    }
}

private struct TranslationPanelIconButtonStyle: ButtonStyle {
    let hoverFill: Color

    func makeBody(configuration: Configuration) -> some View {
        TranslationPanelIconButtonLabel(configuration: configuration, hoverFill: hoverFill)
    }
}

private struct TranslationPanelIconButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    let hoverFill: Color
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered || configuration.isPressed ? hoverFill : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { isHovered = $0 }
    }
}

/// Result body grows with the translation, then scrolls. Buttons stay outside this view.
private struct GrowingResultText: View {
    let text: String
    let isPlaceholder: Bool
    let ink: Color
    let inkFaint: Color

    private let minHeight: CGFloat = 56
    private let maxHeight: CGFloat = 280

    @State private var textHeight: CGFloat = 56

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(isPlaceholder ? inkFaint : ink)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ResultTextHeightKey.self, value: geo.size.height)
                    }
                )
        }
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(ResultTextHeightKey.self) { newValue in
            let next = min(max(ceil(newValue), minHeight), maxHeight)
            if abs(next - textHeight) >= 1 {
                textHeight = next
            }
        }
        .frame(height: min(max(textHeight, minHeight), maxHeight), alignment: .top)
        .clipped()
    }
}

private struct ResultTextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Header-only drag so TextEditor clicks are not eaten by window-move.
private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

private struct AppleTranslationBridge: ViewModifier {
    @ObservedObject var session: TranslationPanelModel

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            AppleTranslationTaskBridge(session: session, content: content)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if canImport(Translation)
@available(macOS 15.0, *)
private struct AppleTranslationTaskBridge<Panel: View>: View {
    @ObservedObject var session: TranslationPanelModel
    let content: Panel
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        content
            .onAppear(perform: applyConfiguration)
            .onChange(of: session.appleRequestID) { _, requestID in
                guard requestID != nil else { return }
                applyConfiguration()
            }
            .translationTask(configuration) { appleSession in
                guard let requestID = session.appleRequestID else { return }
                let text = session.sourceText
                do {
                    let response = try await appleSession.translate(text)
                    session.completeAppleTranslation(requestID: requestID, text: response.targetText)
                } catch is CancellationError {
                    return
                } catch {
                    session.failAppleTranslation(
                        requestID: requestID,
                        message: error.localizedDescription.isEmpty
                            ? TranslatorError.systemFailed.localizedDescription
                            : error.localizedDescription
                    )
                }
            }
    }

    private func applyConfiguration() {
        guard session.appleRequestID != nil else { return }
        let source = Locale.Language(identifier: session.detectedLanguage.appleIdentifier)
        let targetLanguage = session.targetLanguage.resolvedTarget(for: session.detectedLanguage)
        let target = Locale.Language(identifier: targetLanguage.appleIdentifier)
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: source, target: target)
            return
        }
        configuration?.source = source
        configuration?.target = target
        configuration?.invalidate()
    }
}
#endif
