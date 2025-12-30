import Cocoa

class CursorHighlightView: NSView {
    private let manager = CursorHighlightManager.shared
    private let strokeWidth: CGFloat = 2.5

    private var holdRingLayer: CAShapeLayer?

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupHoldRingLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupHoldRingLayer()
    }

    private func setupHoldRingLayer() {
        let ringLayer = CAShapeLayer()
        ringLayer.lineWidth = strokeWidth
        ringLayer.opacity = 0
        layer?.addSublayer(ringLayer)
        holdRingLayer = ringLayer
    }

    func updateHoldRingPosition() {
        guard let window = self.window, let ringLayer = holdRingLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let globalPosition = manager.cursorPosition
        let cursorOnThisScreen = window.screen?.frame.contains(globalPosition) ?? false

        if manager.shouldShowRing && cursorOnThisScreen {
            let windowPoint = window.convertPoint(fromScreen: globalPosition)
            let localPoint = convert(windowPoint, from: nil)

            let size = manager.currentHoldRingSize
            let rect = CGRect(
                x: -size / 2,
                y: -size / 2,
                width: size,
                height: size
            )

            ringLayer.path = CGPath(ellipseIn: rect, transform: nil)
            ringLayer.position = localPoint
            ringLayer.strokeColor = manager.effectColor.withAlphaComponent(0.8).cgColor
            ringLayer.fillColor = manager.effectColor.withAlphaComponent(0.12).cgColor
            ringLayer.opacity = 1
        } else {
            ringLayer.opacity = 0
        }

        CATransaction.commit()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.clear.setFill()
        dirtyRect.fill()

        guard manager.isActive, let window = self.window else { return }

        if let animation = manager.releaseAnimation, !animation.isExpired {
            let windowPoint = window.convertPoint(fromScreen: animation.center)
            let localPoint = convert(windowPoint, from: nil)

            let progress = animation.progress()
            let currentSize = lerp(animation.startSize, animation.maxSize, progress)
            let alpha = 1.0 - progress

            drawRing(
                at: localPoint,
                size: currentSize,
                alpha: alpha
            )
        }
    }

    private func drawRing(at position: NSPoint, size: CGFloat, alpha: Double) {
        let rect = NSRect(
            x: position.x - size / 2,
            y: position.y - size / 2,
            width: size,
            height: size
        )

        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = strokeWidth

        manager.effectColor.withAlphaComponent(0.8 * alpha).setStroke()
        path.stroke()

        manager.effectColor.withAlphaComponent(0.12 * alpha).setFill()
        path.fill()
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }
}
