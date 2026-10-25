import AppKit
import SwiftUI

@MainActor
final class ThumbnailClickNSView: NSView {
    var onSelect: ((Bool, Bool) -> Void)?
    var onOpen: (() -> Void)?

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onOpen?()
        } else {
            let flags = event.modifierFlags
            onSelect?(flags.contains(.command), flags.contains(.shift))
        }
    }
}

struct ThumbnailClickSurface: NSViewRepresentable {
    let onSelect: (Bool, Bool) -> Void
    let onOpen: () -> Void

    @MainActor
    func makeNSView(context: Context) -> ThumbnailClickNSView {
        let view = ThumbnailClickNSView()
        view.onSelect = onSelect
        view.onOpen = onOpen
        return view
    }

    @MainActor
    func updateNSView(_ view: ThumbnailClickNSView, context: Context) {
        view.onSelect = onSelect
        view.onOpen = onOpen
    }
}
