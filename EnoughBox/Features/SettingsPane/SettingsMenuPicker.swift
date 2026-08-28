import AppKit
import SwiftUI

struct SettingsMenuPicker<SelectionValue: Hashable>: NSViewRepresentable {
    @Binding var selection: SelectionValue
    let options: [(SelectionValue, String)]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> SettingsMenuPickerHostView {
        let host = SettingsMenuPickerHostView()
        let popup = host.popupButton
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.selectionChanged(_:))
        context.coordinator.reload(popup)
        return host
    }

    func updateNSView(_ host: SettingsMenuPickerHostView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reload(host.popupButton)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: SettingsMenuPickerHostView,
        context: Context
    ) -> CGSize? {
        CGSize(width: SettingsControlMetrics.width, height: SettingsControlMetrics.height)
    }

    final class Coordinator: NSObject {
        var parent: SettingsMenuPicker

        init(parent: SettingsMenuPicker) {
            self.parent = parent
        }

        func reload(_ popup: NSPopUpButton) {
            popup.removeAllItems()
            for (_, title) in parent.options {
                popup.addItem(withTitle: title)
            }
            if let index = parent.options.firstIndex(where: { $0.0 == parent.selection }) {
                popup.selectItem(at: index)
            }
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard index >= 0, index < parent.options.count else { return }
            parent.selection = parent.options[index].0
        }
    }
}

final class SettingsMenuPickerHostView: NSView {
    let popupButton = NSPopUpButton(frame: .zero, pullsDown: false)

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: SettingsControlMetrics.width,
            height: SettingsControlMetrics.height
        ))
        popupButton.autoresizingMask = [.width, .height]
        addSubview(popupButton)
        popupButton.frame = bounds
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: SettingsControlMetrics.width, height: SettingsControlMetrics.height)
    }
}
