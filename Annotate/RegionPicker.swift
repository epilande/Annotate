import AppKit

/// Capture Area's picker: a crosshair over the display, dimmed outside the rectangle being
/// dragged, with the rectangle's size in points beside it. Release picks the rectangle, and
/// Escape or a right click cancels.
///
/// AppKit only, with no knowledge of the overlay's annotations or of capture: the overlay
/// window installs it over its canvas and forwards the mouse and key events it receives.
/// Drawing goes through layers, so following the pointer never asks the view to redraw.
final class RegionPicker: NSView {
    /// A release whose rectangle is narrower or shorter than this, in points, counts as a
    /// click: nothing is picked and the picker stays open.
    static let minimumSide: CGFloat = 4
    /// How dark the area outside the rectangle gets.
    static let dimOpacity: Float = 0.35

    /// The picker's layers, by name, so tests can find them without relying on their order.
    enum LayerName {
        static let dim = "regionPicker.dim"
        static let border = "regionPicker.border"
        static let sizeLabel = "regionPicker.sizeLabel"
    }

    /// Called with the picked rectangle in this view's coordinates.
    var onPick: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private(set) var dragStart: NSPoint?
    private(set) var dragEnd: NSPoint?

    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let sizeLabel = CATextLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]

        dimLayer.name = LayerName.dim
        borderLayer.name = LayerName.border
        sizeLabel.name = LayerName.sizeLabel
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(CGFloat(Self.dimOpacity)).cgColor
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1
        sizeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sizeLabel.fontSize = 12
        sizeLabel.foregroundColor = NSColor.white.cgColor
        sizeLabel.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        sizeLabel.cornerRadius = 4
        sizeLabel.alignmentMode = .center
        sizeLabel.isHidden = true
        for sublayer in [dimLayer, borderLayer, sizeLabel] {
            layer?.addSublayer(sublayer)
        }
        updateLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The rectangle dragged so far, normalized and clipped to the view, or nil before a drag.
    var selection: CGRect? {
        guard let dragStart, let dragEnd else { return nil }
        return Self.normalizedRect(from: dragStart, to: dragEnd, within: bounds)
    }

    /// The rectangle between two corners, whichever way the drag went, clipped to `bounds`.
    static func normalizedRect(from start: NSPoint, to end: NSPoint, within bounds: CGRect) -> CGRect {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y))
        let clipped = rect.intersection(bounds)
        return clipped.isNull ? CGRect(origin: rect.origin, size: .zero) : clipped
    }

    /// Whether `rect` is big enough to pick rather than a click.
    static func isPickable(_ rect: CGRect) -> Bool {
        rect.width >= minimumSide && rect.height >= minimumSide
    }

    /// The size label's text: whole points, as the rectangle covers on screen.
    static func sizeText(for rect: CGRect) -> String {
        "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
    }

    // MARK: - Events

    /// Handles a mouse event the overlay window forwards. Every mouse event belongs to the
    /// picker while it is open, so nothing reaches the canvas.
    func handleMouseEvent(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch event.type {
        case .leftMouseDown: mouseDown(at: point)
        case .leftMouseDragged: mouseDragged(to: point)
        case .leftMouseUp: mouseUp(at: point)
        case .rightMouseDown, .otherMouseDown: cancel()
        default: break
        }
    }

    func mouseDown(at point: NSPoint) {
        NSCursor.crosshair.set()
        dragStart = point
        dragEnd = point
        updateLayers()
    }

    func mouseDragged(to point: NSPoint) {
        guard dragStart != nil else { return }
        dragEnd = point
        updateLayers()
    }

    func mouseUp(at point: NSPoint) {
        guard dragStart != nil else { return }
        dragEnd = point
        guard let rect = selection, Self.isPickable(rect) else {
            // A click, or a drag too small to mean anything: keep picking.
            dragStart = nil
            dragEnd = nil
            updateLayers()
            return
        }
        onPick?(rect)
    }

    /// Handles a key the overlay window forwards, and returns whether the picker took it.
    /// Escape cancels; every other key is swallowed so no overlay shortcut runs mid-pick.
    @discardableResult
    func handleKey(_ chord: KeyChord) -> Bool {
        if chord.key == "\u{1b}" {
            cancel()
        }
        return true
    }

    func cancel() {
        onCancel?()
    }

    // MARK: - Cursor and layers

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds, options: [.cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    /// The canvas under the picker sets its own cursor on these, so the picker answers first.
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func layout() {
        super.layout()
        updateLayers()
    }

    private func updateLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let dim = CGMutablePath()
        dim.addRect(bounds)
        guard let rect = selection, rect.width > 0, rect.height > 0 else {
            dimLayer.path = dim
            borderLayer.path = nil
            sizeLabel.isHidden = true
            return
        }
        dim.addRect(rect)
        dimLayer.path = dim
        borderLayer.path = CGPath(rect: rect.insetBy(dx: -0.5, dy: -0.5), transform: nil)

        sizeLabel.contentsScale = window?.backingScaleFactor ?? 2
        let text = Self.sizeText(for: rect)
        sizeLabel.string = text
        let textSize = (text as NSString).size(
            withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
        let labelSize = CGSize(width: ceil(textSize.width) + 12, height: ceil(textSize.height) + 4)
        sizeLabel.frame = Self.labelFrame(size: labelSize, for: rect, within: bounds)
        sizeLabel.isHidden = false
    }

    /// Below the rectangle's bottom-right corner, or inside it when that would leave the view.
    static func labelFrame(size: CGSize, for rect: CGRect, within bounds: CGRect) -> CGRect {
        let gap: CGFloat = 6
        var origin = CGPoint(x: rect.maxX - size.width, y: rect.minY - gap - size.height)
        if origin.y < bounds.minY { origin.y = rect.minY + gap }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        return CGRect(origin: origin, size: size)
    }
}
