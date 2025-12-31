import Cocoa

class CursorHighlightView: NSView {
    private let manager = CursorHighlightManager.shared
    private let strokeWidth: CGFloat = 2.5

    private var holdRingLayer: CAShapeLayer?
    private var releaseRingLayer: CAShapeLayer?
    private var spotlightLayer: CAShapeLayer?

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

            // Size based on effect size (slightly smaller than click ring)
            let size = manager.effectSize * 0.5
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
}
