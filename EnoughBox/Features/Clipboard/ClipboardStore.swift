import AppKit
import CryptoKit
import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardItem] = []
    @Published private(set) var filteredEntries: [ClipboardItem] = []
    @Published var query = ""
    @Published var category: ClipboardCategory = ClipboardSettings.selectedCategory
    @Published var selectedIndex = -1
    @Published var isPinned = ClipboardSettings.panelPinned {
        didSet { ClipboardSettings.panelPinned = isPinned }
    }
    @Published private(set) var searchFocusToken = 0
    @Published private(set) var listFocusToken = 0

    private var sortedEntries: [ClipboardItem] = []
    private var timer: Timer?
    private var lastChangeCount = 0
    private var captureInFlight = false
    private var captureGeneration = 0
    private var captureTimeoutTask: Task<Void, Never>?
    private var ignoreChangeCountUpTo = 0
    private var isRunning = false

    private static let persistQueue = DispatchQueue(label: "com.enoughbox.clipboard.persist", qos: .utility)

    init() {
        load()
        refreshDerivedState()
    }

    var selectedEntry: ClipboardItem? {
        let matches = filteredEntries
        guard matches.indices.contains(selectedIndex) else { return nil }
        return matches[selectedIndex]
    }

    func startMonitoring() {
        guard timer == nil else {
            isRunning = true
            return
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureIfChanged()
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
        baselinePasteboard()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        captureGeneration &+= 1
        captureInFlight = false
        captureTimeoutTask?.cancel()
        captureTimeoutTask = nil
    }

    func resetPanelState() {
        query = ""
        rebuildFilteredEntries()
        selectFirstItemIfAvailable()
    }

    private func selectFirstItemIfAvailable() {
        selectedIndex = filteredEntries.isEmpty ? -1 : 0
    }

    func endPanelSession() {
        resetPanelState()
        ClipboardImageStore.clearCache()
    }

    func updateQuery(_ value: String) {
        query = value
        rebuildFilteredEntries()
    }

    func updateCategory(_ value: ClipboardCategory) {
        category = value
        ClipboardSettings.selectedCategory = value
        rebuildFilteredEntries()
        selectFirstItemIfAvailable()
    }

    func moveCategory(by delta: Int) {
        let all = ClipboardCategory.allCases
        guard let index = all.firstIndex(of: category) else { return }
        let next = (index + delta + all.count) % all.count
        updateCategory(all[next])
    }

    func requestSearchFocus() {
        searchFocusToken += 1
    }

    func focusListFromSearch() {
        if filteredEntries.isEmpty {
            selectedIndex = -1
        } else {
            selectedIndex = 0
        }
        listFocusToken += 1
    }

    private func refreshDerivedState() {
        sortedEntries = entries.sorted { $0.copiedAt > $1.copiedAt }
        rebuildFilteredEntries()
    }

    private func rebuildFilteredEntries() {
        let searched = sortedEntries.filter { entry in
            entry.matchesCategory(category) && entry.matchesSearch(query)
        }

        switch category {
        case .recent:
            filteredEntries = searched
                .filter { $0.lastUsedAt != nil }
                .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
                .prefix(ClipboardLimits.recentCount)
                .map { $0 }
        default:
            filteredEntries = searched
        }
        clampSelection()
    }

    func clampSelection() {
        let count = filteredEntries.count
        if count == 0 || selectedIndex < 0 {
            selectedIndex = -1
        } else {
            selectedIndex = min(selectedIndex, count - 1)
        }
    }

    func moveSelection(by delta: Int) {
        let count = filteredEntries.count
        guard count > 0 else {
            selectedIndex = -1
            return
        }
        if selectedIndex < 0 {
            selectedIndex = delta > 0 ? 0 : count - 1
            return
        }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    @discardableResult
    func applySelectedToPasteboard() -> Bool {
        guard let entry = selectedEntry else { return false }
        return applyToPasteboard(entry)
    }

    @discardableResult
    func applyToPasteboard(_ entry: ClipboardItem) -> Bool {
        let applied = ClipboardPasteboardAccess.sync {
            Self.writeEntry(entry, to: NSPasteboard.general)
        }
        guard applied else { return false }
        ignoreNextChange(upTo: NSPasteboard.general.changeCount)
        touch(entry.id)
        return true
    }

    func remove(_ entry: ClipboardItem) {
        entries.removeAll { $0.id == entry.id }
        refreshDerivedState()
        save()
        cleanupPayloadFiles()
    }

    func removeSelected() {
        guard let entry = selectedEntry else { return }
        remove(entry)
    }

    func clearAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        selectedIndex = -1
        refreshDerivedState()
        save()
        cleanupPayloadFiles()
    }

    private func touch(_ entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].lastUsedAt = Date()
        refreshDerivedState()
        save()
    }

    private func ignoreNextChange(upTo changeCount: Int) {
        ignoreChangeCountUpTo = max(ignoreChangeCountUpTo, changeCount)
    }

    private func baselinePasteboard() {
        guard !captureInFlight else { return }
        captureInFlight = true
        captureGeneration &+= 1
        let generation = captureGeneration
        scheduleCaptureTimeout(generation: generation)
        ClipboardPasteboardAccess.async { [weak self] in
            let changeCount = NSPasteboard.general.changeCount
            Task { @MainActor in
                guard let self, self.captureGeneration == generation else { return }
                self.captureInFlight = false
                guard self.isRunning else { return }
                self.lastChangeCount = max(self.lastChangeCount, changeCount)
                self.ignoreChangeCountUpTo = max(self.ignoreChangeCountUpTo, changeCount)
            }
        }
    }

    private func captureIfChanged() {
        guard !captureInFlight else { return }
        let sinceChangeCount = lastChangeCount
        captureInFlight = true
        captureGeneration &+= 1
        let generation = captureGeneration
        scheduleCaptureTimeout(generation: generation)
        ClipboardPasteboardAccess.async { [weak self] in
            let changeCount = NSPasteboard.general.changeCount
            let content: CapturedContent? = changeCount != sinceChangeCount
                ? Self.readPasteboard()
                : nil
            Task { @MainActor in
                guard let self, self.captureGeneration == generation else { return }
                self.captureInFlight = false
                guard changeCount > self.lastChangeCount else { return }
                self.lastChangeCount = changeCount
                guard changeCount > self.ignoreChangeCountUpTo else { return }
                guard self.isRunning, let content else { return }
                switch content {
                case .text(let text):
                    self.promoteText(text)
                case .image(let image):
                    self.promoteImage(image)
                case .files(let paths):
                    self.promoteFiles(paths)
                case .other(let label):
                    self.promoteOther(label: label)
                }
            }
        }
    }

    private func scheduleCaptureTimeout(generation: Int) {
        captureTimeoutTask?.cancel()
        captureTimeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            guard self.captureGeneration == generation, self.captureInFlight else { return }
            self.captureInFlight = false
        }
    }

    private enum CapturedContent {
        case text(String)
        case image((data: Data, width: Int, height: Int))
        case files([String])
        case other(String)
    }

    private static func readPasteboard() -> CapturedContent? {
        let pasteboard = NSPasteboard.general
        let types = (pasteboard.types ?? []).map(\.rawValue)
        if types.contains(ClipboardLimits.concealedPasteboardType) {
            return nil
        }

        if let paths = copiedFilePaths(from: pasteboard) {
            return .files(paths)
        }
        if let image = copiedPNGImage(from: pasteboard) {
            return .image(image)
        }
        if let text = preferredText(from: pasteboard) {
            return .text(text)
        }
        if let label = fallbackLabel(from: pasteboard) {
            return .other(label)
        }
        return nil
    }

    private static func copiedFilePaths(from pasteboard: NSPasteboard) -> [String]? {
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
            !urls.isEmpty,
            urls.count <= ClipboardLimits.maxCopiedFiles
        else { return nil }
        return urls.map { $0.standardizedFileURL.path }
    }

    private static func copiedPNGImage(from pasteboard: NSPasteboard)
        -> (data: Data, width: Int, height: Int)? {
        let png = pasteboard.data(forType: .png)
        guard let source = png ?? pasteboard.data(forType: .tiff),
              source.count <= ClipboardLimits.maxRawImageBytes,
              let rep = NSBitmapImageRep(data: source),
              rep.pixelsWide > 0, rep.pixelsHigh > 0
        else { return nil }
        let data: Data
        if let png {
            data = png
        } else if let converted = rep.representation(using: .png, properties: [:]) {
            data = converted
        } else {
            return nil
        }
        guard data.count <= ClipboardLimits.maxImageBytes else { return nil }
        return (data, rep.pixelsWide, rep.pixelsHigh)
    }

    private static func preferredText(from pasteboard: NSPasteboard) -> String? {
        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return nil }
        guard text.count <= ClipboardLimits.maxTextCharacters else { return nil }
        return text
    }

    private static func fallbackLabel(from pasteboard: NSPasteboard) -> String? {
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard !types.isEmpty else { return nil }
        return types.joined(separator: ", ")
    }

    private func promoteText(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let existing = entries.first(where: { $0.kind == .text && $0.resolvedText() == text }) {
            entries.removeAll { $0.id == existing.id }
            insertPromoted(makeTextItem(text: text, existingID: existing.id, copiedAt: Date()))
        } else {
            insertPromoted(makeTextItem(text: text))
        }
        refreshDerivedState()
        trimToLimit()
        save()
    }

    private func makeTextItem(text: String, existingID: UUID = UUID(), copiedAt: Date = Date()) -> ClipboardItem {
        if let textFile = ClipboardTextStore.store(text) {
            return ClipboardItem(
                id: existingID,
                copiedAt: copiedAt,
                kind: .text,
                text: String(text.prefix(ClipboardLimits.previewCharacters)),
                textFile: textFile
            )
        }
        return ClipboardItem(id: existingID, copiedAt: copiedAt, kind: .text, text: text)
    }

    private func promoteImage(_ image: (data: Data, width: Int, height: Int)) {
        let hash = Self.sha256Hex(image.data)
        if let existing = entries.first(where: { $0.kind == .image && $0.imageHash == hash }) {
            entries.removeAll { $0.id == existing.id }
            insertPromoted(ClipboardItem(
                id: existing.id,
                copiedAt: Date(),
                kind: .image,
                imageFile: existing.imageFile,
                imageHash: hash,
                imageWidth: existing.imageWidth,
                imageHeight: existing.imageHeight
            ))
        } else {
            guard let name = ClipboardImageStore.store(image.data) else { return }
            insertPromoted(ClipboardItem(
                kind: .image,
                imageFile: name,
                imageHash: hash,
                imageWidth: image.width,
                imageHeight: image.height
            ))
        }
        refreshDerivedState()
        trimToLimit()
        save()
        cleanupPayloadFiles()
    }

    private func promoteFiles(_ paths: [String]) {
        if let existing = entries.first(where: { $0.kind == .other && $0.filePaths == paths }) {
            entries.removeAll { $0.id == existing.id }
            insertPromoted(ClipboardItem(
                id: existing.id,
                copiedAt: Date(),
                kind: .other,
                filePaths: paths
            ))
        } else {
            insertPromoted(ClipboardItem(kind: .other, filePaths: paths))
        }
        refreshDerivedState()
        trimToLimit()
        save()
    }

    private func promoteOther(label: String) {
        let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let existing = entries.first(where: { $0.kind == .other && $0.text == text && $0.filePaths.isEmpty }) {
            entries.removeAll { $0.id == existing.id }
            insertPromoted(ClipboardItem(
                id: existing.id,
                copiedAt: Date(),
                kind: .other,
                text: text
            ))
        } else {
            insertPromoted(ClipboardItem(kind: .other, text: text))
        }
        refreshDerivedState()
        trimToLimit()
        save()
    }

    private func insertPromoted(_ entry: ClipboardItem) {
        entries.insert(entry, at: 0)
    }

    private func trimToLimit() {
        let limit = ClipboardSettings.historyLimit
        guard entries.count > limit else { return }
        entries = Array(entries.prefix(limit))
        refreshDerivedState()
        cleanupPayloadFiles()
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func writeEntry(_ entry: ClipboardItem, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        switch entry.kind {
        case .text:
            let text = entry.resolvedText()
            guard !text.isEmpty else { return false }
            return pasteboard.setString(text, forType: .string)
        case .image:
            guard let name = entry.imageFile,
                  let data = ClipboardImageStore.imageData(named: name),
                  let image = NSImage(data: data)
            else { return false }
            pasteboard.writeObjects([image])
            return true
        case .other:
            if !entry.filePaths.isEmpty {
                let urls = entry.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
                return pasteboard.writeObjects(urls)
            }
            guard !entry.text.isEmpty else { return false }
            return pasteboard.setString(entry.text, forType: .string)
        }
    }

    private func load() {
        AppPaths.ensureClipboardDirectories()
        guard let data = try? Data(contentsOf: AppPaths.clipboardIndexFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let loaded = try? decoder.decode([ClipboardItem].self, from: data) else { return }
        entries = loaded.sorted { $0.copiedAt > $1.copiedAt }
        refreshDerivedState()
        cleanupPayloadFiles()
    }

    private func save() {
        let snapshot = entries
        Self.persistQueue.async {
            Self.writeSnapshot(snapshot)
        }
    }

    private static func writeSnapshot(_ entries: [ClipboardItem]) {
        AppPaths.ensureClipboardDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: AppPaths.clipboardIndexFile, options: .atomic)
    }

    private func cleanupPayloadFiles() {
        let imageNames = Set(entries.compactMap(\.imageFile))
        let textNames = Set(entries.compactMap(\.textFile))
        ClipboardImageStore.cleanup(keeping: imageNames)
        ClipboardTextStore.cleanup(keeping: textNames)
    }
}
