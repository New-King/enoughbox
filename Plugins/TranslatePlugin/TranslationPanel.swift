import AppKit
import AVFoundation
import Combine
import SwiftUI

@MainActor
final class TranslationSession: ObservableObject {
    @Published var sourceRevision = UUID()
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var isPinned = false
    @Published var isTranslating = false
    @Published var targetLanguage = TranslateSettings.targetLanguage
    @Published var detectedLanguage: TranslateLanguage = .en
    @Published var debugLine = ""
    @Published var logPath = ""

    private var translateTask: Task<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()

    func present(sourceText: String, debugLine: String, logPath: String) {
        sourceRevision = UUID()
        self.sourceText = sourceText
        self.debugLine = debugLine
        self.logPath = logPath
        targetLanguage = TranslateSettings.targetLanguage
        detectedLanguage = LanguageDetector.detect(sourceText)
        if sourceText.isEmpty {
            translatedText = ""
            isTranslating = false
            return
        }
        translate()
    }

    func translate() {
        TranslateSettings.targetLanguage = targetLanguage
        detectedLanguage = LanguageDetector.detect(sourceText)
        let text = sourceText
        let target = targetLanguage
        translateTask?.cancel()
        isTranslating = true
        translateTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            translatedText = MockTranslator.translate(text, to: target)
            isTranslating = false
        }
    }

    func swapLanguages() {
        let previousSource = sourceText
        sourceText = translatedText.replacingOccurrences(
            of: "\n\n\(TranslateL10n.string("plugin.translate.mock.note"))",
            with: ""
        )
        if sourceText.hasPrefix(TranslateL10n.string("plugin.translate.mock.note")) {
            sourceText = previousSource
        }
        let previousTarget = targetLanguage
        targetLanguage = detectedLanguage
        detectedLanguage = previousTarget
        TranslateSettings.targetLanguage = targetLanguage
        if !sourceText.isEmpty {
            translate()
        }
    }

    func clearSource() {
        sourceText = ""
        translatedText = ""
    }

    func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func speak(_ text: String, language: TranslateLanguage) {
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.speechLanguage)
        synthesizer.speak(utterance)
    }
}

@MainActor
final class TranslationPanelController: NSWindowController {
    private let session = TranslationSession()

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 468),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.init(window: panel)
        panel.contentViewController = NSHostingController(
            rootView: TranslationPanelView(
                session: session,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )
        session.$isPinned
            .receive(on: RunLoop.main)
            .sink { [weak panel] pinned in
                panel?.level = pinned ? .statusBar : .floating
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func present(sourceText: String, debugLine: String, logPath: String) {
        session.present(sourceText: sourceText, debugLine: debugLine, logPath: logPath)
        guard let window else { return }
        positionNearMouse(window)
        window.orderFrontRegardless()
        window.makeKey()
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

private struct TranslationPanelView: View {
    @ObservedObject var session: TranslationSession
    @Environment(\.colorScheme) private var colorScheme
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            header
            sourceCard
            languageBar
            resultCard
            if !session.debugLine.isEmpty {
                debugCard
            }
        }
        .padding(12)
        .background(tokens.page)
        .frame(width: 380)
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
                panelIconButton("plus.viewfinder") {}
                    .disabled(true)
                    .help(TranslateL10n.string("plugin.translate.ocr.later"))
                panelIconButton("xmark.square") {
                    session.clearSource()
                }

                languageChip(session.detectedLanguage.localizedName)

                Spacer(minLength: 8)

                Button(action: session.translate) {
                    HStack(spacing: 4) {
                        Image(systemName: "character.book.closed")
                        Text("plugin.translate.action", bundle: TranslateL10n.bundle)
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
            Text("plugin.translate.source.auto", bundle: TranslateL10n.bundle)
                .font(.system(size: 12))
                .foregroundStyle(tokens.inkSoft)
            Spacer()
            Button(action: session.swapLanguages) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tokens.inkMuted)
            }
            .buttonStyle(.plain)
            .help(TranslateL10n.string("plugin.translate.swap"))
            Spacer()
            Picker("", selection: $session.targetLanguage) {
                ForEach(TranslateLanguage.allCases) { language in
                    Text(language.localizedName).tag(language)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            .onChange(of: session.targetLanguage) { _, _ in
                if !session.sourceText.isEmpty {
                    session.translate()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.ink)
                Text("plugin.translate.engine.mock", bundle: TranslateL10n.bundle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.ink)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.inkFaint)
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
                    Text(session.translatedText.isEmpty ? TranslateL10n.string("plugin.translate.result.empty") : session.translatedText)
                        .font(.system(size: 14))
                        .foregroundStyle(session.translatedText.isEmpty ? tokens.inkFaint : tokens.ink)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 10)

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
        }
        .background(tokens.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(tokens.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var debugCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("plugin.translate.debug.title", bundle: TranslateL10n.bundle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.inkMuted)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    let payload = session.debugLine + "\n" + session.logPath
                    NSPasteboard.general.setString(payload, forType: .string)
                } label: {
                    Text("plugin.translate.debug.copy", bundle: TranslateL10n.bundle)
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.inkSoft)
                }
                .buttonStyle(.plain)
            }
            Text(session.debugLine)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(tokens.inkMuted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !session.logPath.isEmpty {
                Text(session.logPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tokens.inkFaint)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(tokens.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }

    private var tokens: PanelTokens {
        PanelTokens.tokens(for: colorScheme)
    }
}

/// Matches host `DesignTokens` so the floating panel stays grayscale.
private struct PanelTokens {
    let page: Color
    let card: Color
    let ink: Color
    let inkSoft: Color
    let inkMuted: Color
    let inkFaint: Color
    let accent: Color
    let accentSoft: Color
    let border: Color

    static func tokens(for colorScheme: ColorScheme) -> PanelTokens {
        colorScheme == .dark ? .dark : .light
    }

    static let light = PanelTokens(
        page: Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255),
        card: Color.white,
        ink: Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255),
        inkSoft: Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255),
        inkMuted: Color(red: 110 / 255, green: 110 / 255, blue: 115 / 255),
        inkFaint: Color(red: 134 / 255, green: 134 / 255, blue: 139 / 255),
        accent: Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255),
        accentSoft: Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255),
        border: Color.black.opacity(0.08)
    )

    static let dark = PanelTokens(
        page: Color(red: 36 / 255, green: 36 / 255, blue: 38 / 255),
        card: Color(red: 48 / 255, green: 48 / 255, blue: 50 / 255),
        ink: Color(red: 224 / 255, green: 224 / 255, blue: 224 / 255),
        inkSoft: Color(red: 198 / 255, green: 198 / 255, blue: 201 / 255),
        inkMuted: Color(red: 176 / 255, green: 176 / 255, blue: 179 / 255),
        inkFaint: Color(red: 148 / 255, green: 148 / 255, blue: 151 / 255),
        accent: Color(red: 72 / 255, green: 72 / 255, blue: 73 / 255),
        accentSoft: Color(red: 42 / 255, green: 42 / 255, blue: 44 / 255),
        border: Color.white.opacity(0.12)
    )
}
