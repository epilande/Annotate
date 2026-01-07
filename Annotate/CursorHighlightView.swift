import Cocoa

class CursorHighlightView: NSView {
    private let manager = CursorHighlightManager.shared
    private let strokeWidth: CGFloat = 2.5

    private var holdRingLayer: CAShapeLayer?
    private var releaseRingLayer: CAShapeLayer?
    private var spotlightLayer: CAShapeLayer?
    private var activeCursorLayer: CAShapeLayer?
    private var activeCursorOutlineLayer: CAShapeLayer?

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupLayers()
    }

    private func setupLayers() {
        // Spotlight layer (follows cursor when enabled)
        let spotlight = CAShapeLayer()
        spotlight.lineWidth = 0
        spotlight.opacity = 0
        layer?.addSublayer(spotlight)
        spotlightLayer = spotlight

        // Hold ring layer (shown while mouse is down)
        let holdLayer = CAShapeLayer()
        holdLayer.lineWidth = strokeWidth
        holdLayer.fillColor = nil
        holdLayer.opacity = 0
        layer?.addSublayer(holdLayer)
        holdRingLayer = holdLayer

        // Release ring layer (expands and fades on mouse up)
        let releaseLayer = CAShapeLayer()
        releaseLayer.lineWidth = strokeWidth
        releaseLayer.fillColor = nil
        releaseLayer.opacity = 0
        layer?.addSublayer(releaseLayer)
        releaseRingLayer = releaseLayer

        // Active cursor outline layer (drawn first, behind the fill)
        let cursorOutline = CAShapeLayer()
        cursorOutline.lineWidth = 1.5
        cursorOutline.opacity = 0
        layer?.addSublayer(cursorOutline)
        activeCursorOutlineLayer = cursorOutline

        // Active cursor layer (overlay indicator)
        let cursorLayer = CAShapeLayer()
        cursorLayer.lineWidth = 1.0
        cursorLayer.opacity = 0
        layer?.addSublayer(cursorLayer)
        activeCursorLayer = cursorLayer
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

    func updateReleaseAnimation() {
        guard let window = self.window, let ringLayer = releaseRingLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if let animation = manager.releaseAnimation, !animation.isExpired {
            let windowPoint = window.convertPoint(fromScreen: animation.center)
            let localPoint = convert(windowPoint, from: nil)

            let progress = animation.progress()
            let currentSize = lerp(animation.startSize, animation.maxSize, progress)
            let alpha = Float(1.0 - progress)

            let rect = CGRect(
                x: -currentSize / 2,
                y: -currentSize / 2,
                width: currentSize,
                height: currentSize
            )

            ringLayer.path = CGPath(ellipseIn: rect, transform: nil)
            ringLayer.position = localPoint
            ringLayer.strokeColor = manager.effectColor.withAlphaComponent(0.8).cgColor
            ringLayer.fillColor = manager.effectColor.withAlphaComponent(0.12).cgColor
            ringLayer.opacity = alpha
        } else {
            ringLayer.opacity = 0
        }

        CATransaction.commit()
    }

    func updateSpotlightPosition() {
        guard let window = self.window, let spotlight = spotlightLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let globalPosition = manager.cursorPosition
        let cursorOnThisScreen = window.screen?.frame.contains(globalPosition) ?? false

        if manager.shouldShowCursorHighlight && cursorOnThisScreen {
            let windowPoint = window.convertPoint(fromScreen: globalPosition)
            let localPoint = convert(windowPoint, from: nil)

            let size = manager.spotlightSize
            let rect = CGRect(
                x: -size / 2,
                y: -size / 2,
                width: size,
                height: size
            )

            spotlight.path = CGPath(ellipseIn: rect, transform: nil)
            spotlight.position = localPoint

            // Filled circle with glow effect via shadow
            let color = manager.effectColor
            spotlight.fillColor = color.withAlphaComponent(0.3).cgColor
            spotlight.shadowColor = color.cgColor
            spotlight.shadowRadius = size * 0.4
            spotlight.shadowOpacity = 0.6
            spotlight.shadowOffset = .zero
            spotlight.opacity = 1
        } else {
            spotlight.opacity = 0
        }

        CATransaction.commit()
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }

    // MARK: - Active Cursor

    func updateActiveCursor() {
        guard let window = self.window,
              let cursorLayer = activeCursorLayer,
              let outlineLayer = activeCursorOutlineLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let globalPosition = manager.cursorPosition
        let cursorOnThisScreen = window.screen?.frame.contains(globalPosition) ?? false

        if manager.shouldShowActiveCursor && cursorOnThisScreen {
            let windowPoint = window.convertPoint(fromScreen: globalPosition)
            let localPoint = convert(windowPoint, from: nil)

            let color = manager.annotationColor
            let contrastColor = color.contrastingColor()

            switch manager.activeCursorStyle {
            case .none:
                cursorLayer.opacity = 0
                outlineLayer.opacity = 0

            case .outline:
                let path = createArrowPath()
                cursorLayer.path = path
                cursorLayer.position = localPoint
                cursorLayer.fillColor = NSColor.black.cgColor
                cursorLayer.strokeColor = color.cgColor
                cursorLayer.lineWidth = 1.0
                cursorLayer.opacity = 1

                outlineLayer.opacity = 0

            case .dot:
                let size: CGFloat = 20
                let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
                let path = CGPath(ellipseIn: rect, transform: nil)

                // Outline layer (contrast)
                outlineLayer.path = path
                outlineLayer.position = localPoint
                outlineLayer.fillColor = nil
                outlineLayer.strokeColor = contrastColor.cgColor
                outlineLayer.lineWidth = 3.0
                outlineLayer.opacity = 1

                // Main layer (filled with color)
                cursorLayer.path = path
                cursorLayer.position = localPoint
                cursorLayer.fillColor = color.cgColor
                cursorLayer.strokeColor = nil
                cursorLayer.lineWidth = 0
                cursorLayer.opacity = 1

            case .crosshair:
                let size: CGFloat = 20
                let thickness: CGFloat = 2.5
                let path = createCrosshairPath(size: size, thickness: thickness)

                // Outline layer (contrast)
                outlineLayer.path = path
                outlineLayer.position = localPoint
                outlineLayer.fillColor = nil
                outlineLayer.strokeColor = contrastColor.cgColor
                outlineLayer.lineWidth = 3.0
                outlineLayer.opacity = 1

                // Main layer (colored stroke)
                cursorLayer.path = path
                cursorLayer.position = localPoint
                cursorLayer.fillColor = nil
                cursorLayer.strokeColor = color.cgColor
                cursorLayer.lineWidth = thickness
                cursorLayer.opacity = 1
            }
        } else {
            cursorLayer.opacity = 0
            outlineLayer.opacity = 0
        }

        CATransaction.commit()
    }

    /// Creates a macOS-style arrow cursor path
    private func createArrowPath() -> CGPath {
        let path = CGMutablePath()
        // Arrow pointing up-left, with tip at origin
        // Coordinates are in view space (y increases upward in non-flipped view)
        path.move(to: CGPoint(x: 0, y: 0))           // Tip
        path.addLine(to: CGPoint(x: 0, y: -17))     // Left edge down
        path.addLine(to: CGPoint(x: 4, y: -13))     // Notch inner
        path.addLine(to: CGPoint(x: 8, y: -21))     // Tail bottom-left
        path.addLine(to: CGPoint(x: 11, y: -19))    // Tail bottom-right
        path.addLine(to: CGPoint(x: 7, y: -11))     // Back to body
        path.addLine(to: CGPoint(x: 12, y: -11))    // Right point
        path.closeSubpath()
        return path
    }

    /// Creates a crosshair (+) path
    private func createCrosshairPath(size: CGFloat, thickness: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let halfSize = size / 2

        // Horizontal line
        path.move(to: CGPoint(x: -halfSize, y: 0))
        path.addLine(to: CGPoint(x: halfSize, y: 0))

        // Vertical line
        path.move(to: CGPoint(x: 0, y: -halfSize))
        path.addLine(to: CGPoint(x: 0, y: halfSize))

        return path
    }
}
