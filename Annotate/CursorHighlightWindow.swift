import Cocoa

class CursorHighlightWindow: NSPanel {
    var highlightView: CursorHighlightView!

    private var animationTimer: Timer?
    private let animationInterval: TimeInterval = 1.0 / 60.0

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: backingStoreType,
            defer: flag
        )

        configureWindow()
        setupHighlightView()
    }

    private func configureWindow() {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        // Window level above normal windows but below overlay
        let overlayLevel = [
            CGWindowLevelForKey(.mainMenuWindow),
            CGWindowLevelForKey(.statusWindow),
            CGWindowLevelForKey(.popUpMenuWindow),
            CGWindowLevelForKey(.assistiveTechHighWindow),
            CGWindowLevelForKey(.screenSaverWindow),
        ].map { Int($0) }.max() ?? Int(CGWindowLevelForKey(.statusWindow))

        level = NSWindow.Level(rawValue: overlayLevel)
    }

    private func setupHighlightView() {
        highlightView = CursorHighlightView(frame: contentRect(forFrameRect: frame))
        highlightView.wantsLayer = true
        highlightView.autoresizingMask = [.width, .height]
        contentView = highlightView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Animation Loop

    func startAnimationLoop() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(
            timeInterval: animationInterval,
            target: self,
            selector: #selector(updateAnimation),
            userInfo: nil,
            repeats: true
        )
        RunLoop.current.add(animationTimer!, forMode: .common)
    }

    func stopAnimationLoop() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    @objc private func updateAnimation() {
        let manager = CursorHighlightManager.shared

        highlightView.updateHoldRingPosition()

        let hadAnimation = manager.hasActiveAnimation
        manager.cleanupExpiredAnimation()

        if manager.hasActiveAnimation || hadAnimation {
            highlightView.needsDisplay = true
        }

        if !manager.shouldShowRing && !manager.hasActiveAnimation {
            stopAnimationLoop()
        }
    }

    // MARK: - Visibility

    func updateVisibility() {
        let manager = CursorHighlightManager.shared

        if manager.isActive {
            orderFront(nil)
            startAnimationLoop()
        } else {
            orderOut(nil)
            stopAnimationLoop()
        }
    }
}
