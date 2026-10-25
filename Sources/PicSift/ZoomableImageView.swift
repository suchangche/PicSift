import AppKit
import SwiftUI

@MainActor
final class ZoomController: ObservableObject {
    @Published fileprivate(set) var scale = 1.0
    fileprivate weak var imageView: ZoomImageView?

    func zoomIn() { imageView?.zoom(by: 1.25) }
    func zoomOut() { imageView?.zoom(by: 0.8) }
    func fit() { imageView?.resetZoom() }

    fileprivate func attach(_ view: ZoomImageView) {
        imageView = view
        scale = view.zoomScale
    }

    fileprivate func zoomDidChange(_ scale: CGFloat) {
        let newValue = Double(scale)
        guard abs(self.scale - newValue) > 0.0001 else { return }
        self.scale = newValue
    }
}

@MainActor
final class ZoomImageView: NSView {
    weak var zoomController: ZoomController?
    var displayedImage: NSImage? {
        didSet {
            resetZoom()
        }
    }

    private(set) var zoomScale: CGFloat = 1
    private var offset = CGPoint.zero
    private var lastDragLocation: CGPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        constrainOffset()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(rect: dirtyRect).fill()
        guard let displayedImage, !bounds.isEmpty else { return }

        NSGraphicsContext.current?.imageInterpolation = .high
        displayedImage.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    override func magnify(with event: NSEvent) {
        zoom(at: convert(event.locationInWindow, from: nil), by: 1 + event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let precisePan = event.hasPreciseScrollingDeltas
            && zoomScale > 1
            && !event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.control)

        if precisePan {
            offset.x += event.scrollingDeltaX
            offset.y += event.scrollingDeltaY
            constrainOffset()
            needsDisplay = true
        } else {
            let factor = exp(event.scrollingDeltaY * 0.035)
            zoom(at: location, by: factor)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 {
            if zoomScale > 1.001 {
                resetZoom()
            } else {
                zoom(at: location, by: 2)
            }
        } else {
            lastDragLocation = location
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard zoomScale > 1, let lastDragLocation else { return }
        let location = convert(event.locationInWindow, from: nil)
        offset.x += location.x - lastDragLocation.x
        offset.y += location.y - lastDragLocation.y
        self.lastDragLocation = location
        constrainOffset()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        lastDragLocation = nil
    }

    func zoom(by factor: CGFloat) {
        zoom(at: CGPoint(x: bounds.midX, y: bounds.midY), by: factor)
    }

    func resetZoom() {
        zoomScale = 1
        offset = .zero
        notifyZoomChanged()
        needsDisplay = true
    }

    private var pixelSize: CGSize? {
        guard let displayedImage else { return nil }
        let widest = displayedImage.representations.max {
            $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
        }
        let width = widest?.pixelsWide ?? Int(displayedImage.size.width)
        let height = widest?.pixelsHigh ?? Int(displayedImage.size.height)
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private var imageRect: CGRect {
        guard let pixelSize else { return .zero }
        let fitScale = min(bounds.width / pixelSize.width, bounds.height / pixelSize.height)
        let width = pixelSize.width * fitScale * zoomScale
        let height = pixelSize.height * fitScale * zoomScale
        return CGRect(
            x: bounds.midX - width / 2 + offset.x,
            y: bounds.midY - height / 2 + offset.y,
            width: width,
            height: height
        )
    }

    private func zoom(at anchor: CGPoint, by factor: CGFloat) {
        guard pixelSize != nil, !bounds.isEmpty else { return }
        let oldScale = zoomScale
        let newScale = min(40, max(1, oldScale * factor))
        guard abs(oldScale - newScale) > 0.0001 else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let relativeAnchor = CGPoint(
            x: anchor.x - center.x - offset.x,
            y: anchor.y - center.y - offset.y
        )
        let ratio = newScale / oldScale
        offset = CGPoint(
            x: anchor.x - center.x - relativeAnchor.x * ratio,
            y: anchor.y - center.y - relativeAnchor.y * ratio
        )
        zoomScale = newScale
        if newScale == 1 { offset = .zero }
        constrainOffset()
        notifyZoomChanged()
        needsDisplay = true
    }

    private func constrainOffset() {
        guard zoomScale > 1, let pixelSize else {
            offset = .zero
            return
        }
        let fitScale = min(bounds.width / pixelSize.width, bounds.height / pixelSize.height)
        let scaledSize = CGSize(
            width: pixelSize.width * fitScale * zoomScale,
            height: pixelSize.height * fitScale * zoomScale
        )
        let maximumX = abs(scaledSize.width - bounds.width) / 2
        let maximumY = abs(scaledSize.height - bounds.height) / 2
        offset.x = min(maximumX, max(-maximumX, offset.x))
        offset.y = min(maximumY, max(-maximumY, offset.y))
    }

    private func notifyZoomChanged() {
        let controller = zoomController
        let scale = zoomScale
        Task { @MainActor in
            controller?.zoomDidChange(scale)
        }
    }
}

struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage?
    @ObservedObject var controller: ZoomController

    @MainActor
    func makeNSView(context: Context) -> ZoomImageView {
        let view = ZoomImageView()
        view.zoomController = controller
        controller.attach(view)
        view.displayedImage = image
        return view
    }

    @MainActor
    func updateNSView(_ view: ZoomImageView, context: Context) {
        if view.displayedImage !== image {
            view.displayedImage = image
        }
    }
}
