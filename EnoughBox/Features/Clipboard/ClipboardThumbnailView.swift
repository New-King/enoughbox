import AppKit
import SwiftUI

/// Loads image thumbnails off the main thread; drops decoded images on disappear.
struct ClipboardThumbnailView: View {
    @Environment(\.designTokens) private var tokens
    let imageFile: String?
    let size: CGFloat

    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .task(id: imageFile) {
            await loadThumbnail()
        }
        .onDisappear {
            thumbnail = nil
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tokens.inkMuted)
            .frame(width: size, height: size)
            .background(tokens.page, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @MainActor
    private func loadThumbnail() async {
        thumbnail = nil
        guard let imageFile else { return }
        let loaded = await Task.detached(priority: .utility) {
            ClipboardImageStore.thumbnail(named: imageFile)
        }.value
        guard !Task.isCancelled else { return }
        thumbnail = loaded
    }
}
