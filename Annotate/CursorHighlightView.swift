import Cocoa

class CursorHighlightView: NSView {
    private let manager = CursorHighlightManager.shared
    private let strokeWidth: CGFloat = 2.5

    private var holdRingLayer: CAShapeLayer?
    private var releaseRingLayer: CAShapeLayer?
    private var spotlightLayer: CAShapeLayer?
    private var activeCursorLayer: CAShapeLayer?
    private var activeCursorOutlineLayer: CAShapeLayer?

    // MARK: - Cached Paths (avoid per-frame allocations)

    private var cachedSpotlightPath: CGPath?
    private var cachedSpotlightSize: CGFloat = 0

    private var cachedCircleOuterPath: CGPath?
    private var cachedCircleInnerPath: CGPath?
    private var cachedCircleSize: CGFloat = 0

    private var cachedCrosshairPath: CGPath?
    private var cachedCrosshairSize: CGFloat = 0

    // MARK: - Position Tracking (skip redundant updates)

    private var lastSpotlightPosition: CGPoint = .zero
    private var lastSpotlightVisible: Bool = false
    private var lastSpotlightShadowSize: CGFloat = 0

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

        let cursorOutline = CAShapeLayer()
        cursorOutline.opacity = 0
        layer?.addSublayer(cursorOutline)
        activeCursorOutlineLayer = cursorOutline

        let cursorLayer = CAShapeLayer()
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
            ringLayer.strokeColor = manager.effectColorStrokeCG
            ringLayer.fillColor = manager.effectColorFillCG
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
            ringLayer.strokeColor = manager.effectColorStrokeCG
            ringLayer.fillColor = manager.effectColorFillCG
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
            spotlight.path = spotlightPath(for: size)

            // Only update position if changed
            if localPoint != lastSpotlightPosition {
                spotlight.position = localPoint
                lastSpotlightPosition = localPoint
            }

            // Only update shadow properties when becoming visible or size changed
            let needsShadowUpdate = !lastSpotlightVisible || size != lastSpotlightShadowSize
            if needsShadowUpdate {
                spotlight.fillColor = manager.effectColorSpotlightCG
                spotlight.shadowColor = manager.effectColorCG
                spotlight.shadowRadius = size * 0.4
                spotlight.shadowOpacity = 0.6
                spotlight.shadowOffset = .zero
                lastSpotlightShadowSize = size
            }
            spotlight.opacity = 1
            lastSpotlightVisible = true
        } else {
            spotlight.opacity = 0
            lastSpotlightVisible = false
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
        let screenHasActiveOverlay = window.screen.map { manager.isOverlayActiveOnScreen($0) } ?? false

        if screenHasActiveOverlay && cursorOnThisScreen && manager.activeCursorStyle != .none {
            let windowPoint = window.convertPoint(fromScreen: globalPosition)
            let localPoint = convert(windowPoint, from: nil)

            switch manager.activeCursorStyle {
            case .outline:
                outlineLayer.path = Self.cursorOuterPath
                outlineLayer.position = localPoint
                outlineLayer.fillColor = manager.annotationColorCG
                outlineLayer.strokeColor = nil
                outlineLayer.lineWidth = 0
                outlineLayer.opacity = 1

                cursorLayer.path = Self.cursorInnerPath
                cursorLayer.position = localPoint
                cursorLayer.fillColor = Self.blackCG
                cursorLayer.strokeColor = nil
                cursorLayer.lineWidth = 0
                cursorLayer.opacity = 1

            case .circle:
                let size = manager.activeCursorSize
                let strokeWidth = max(2.0, size / 10)
                let paths = circlePaths(for: size)

                outlineLayer.path = paths.outer
                outlineLayer.position = localPoint
                outlineLayer.fillColor = nil
                outlineLayer.strokeColor = manager.annotationColorCG
                outlineLayer.lineWidth = strokeWidth
                outlineLayer.opacity = 1

                cursorLayer.path = paths.inner
                cursorLayer.position = localPoint
                cursorLayer.fillColor = manager.annotationColorCG
                cursorLayer.strokeColor = nil
                cursorLayer.lineWidth = 0
                cursorLayer.opacity = 1

            case .crosshair:
                let size = manager.activeCursorSize
                let thickness = max(2.5, size / 5)

                outlineLayer.opacity = 0

                cursorLayer.path = crosshairPath(for: size)
                cursorLayer.position = localPoint
                cursorLayer.fillColor = nil
                cursorLayer.strokeColor = manager.annotationColorCG
                cursorLayer.lineWidth = thickness
                cursorLayer.opacity = 1

            case .none:
                break
            }
        } else {
            cursorLayer.opacity = 0
            outlineLayer.opacity = 0
        }

        CATransaction.commit()
    }

    // MARK: - Cached Path Helpers

    private func spotlightPath(for size: CGFloat) -> CGPath {
        if size != cachedSpotlightSize || cachedSpotlightPath == nil {
            let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
            cachedSpotlightPath = CGPath(ellipseIn: rect, transform: nil)
            cachedSpotlightSize = size
        }
        return cachedSpotlightPath!
    }

    private func circlePaths(for size: CGFloat) -> (outer: CGPath, inner: CGPath) {
        if size != cachedCircleSize || cachedCircleOuterPath == nil {
            let innerSize = size * 0.4
            let outerRect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
            let innerRect = CGRect(x: -innerSize / 2, y: -innerSize / 2, width: innerSize, height: innerSize)
            cachedCircleOuterPath = CGPath(ellipseIn: outerRect, transform: nil)
            cachedCircleInnerPath = CGPath(ellipseIn: innerRect, transform: nil)
            cachedCircleSize = size
        }
        return (cachedCircleOuterPath!, cachedCircleInnerPath!)
    }

    private func crosshairPath(for size: CGFloat) -> CGPath {
        if size != cachedCrosshairSize || cachedCrosshairPath == nil {
            let path = CGMutablePath()
            let halfSize = size / 2
            path.move(to: CGPoint(x: -halfSize, y: 0))
            path.addLine(to: CGPoint(x: halfSize, y: 0))
            path.move(to: CGPoint(x: 0, y: -halfSize))
            path.addLine(to: CGPoint(x: 0, y: halfSize))
            cachedCrosshairPath = path
            cachedCrosshairSize = size
        }
        return cachedCrosshairPath!
    }

    // MARK: - Static Constants

    private static let blackCG: CGColor = NSColor.black.cgColor

    private static let cursorOuterPath: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 1))
        path.addLine(to: CGPoint(x: 0, y: -15))
        path.addLine(to: CGPoint(x: 3.3, y: -12.2))
        path.addLine(to: CGPoint(x: 6.1, y: -17.5))
        path.addLine(to: CGPoint(x: 8, y: -16.5))
        path.addLine(to: CGPoint(x: 9.6, y: -15.6))
        path.addLine(to: CGPoint(x: 7, y: -10.8))
        path.addLine(to: CGPoint(x: 11.4, y: -10.8))
        path.closeSubpath()
        return path
    }()

    private static let cursorInnerPath: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1, y: -1.8))
        path.addLine(to: CGPoint(x: 1, y: -13))
        path.addLine(to: CGPoint(x: 3.5, y: -10.6))
        path.addLine(to: CGPoint(x: 6.3, y: -15.8))
        path.addLine(to: CGPoint(x: 8.2, y: -14.9))
        path.addLine(to: CGPoint(x: 5.4, y: -9.7))
        path.addLine(to: CGPoint(x: 9, y: -9.7))
        path.closeSubpath()
        return path
    }()
}
