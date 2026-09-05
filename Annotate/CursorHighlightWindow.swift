import Cocoa

class CursorHighlightWindow: NSPanel {
    var highlightView: CursorHighlightView!

    var animationDisplayLink: CADisplayLink?

    // Track previous frame state to ensure update functions run one extra frame
    // when transitioning to inactive (needed to set layer opacity to 0)
    private var wasShowingSpotlight = false
    private var wasShowingRing = false
    private var wasShowingReleaseAnimation = false
    private var wasShowingActiveCursor = false

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
        isRestorable = false
        hidesOnDeactivate = false  // Stay visible even when app is hidden
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        // Window level above overlay window so cursor highlight is visible when annotating
        let levels = [
            CGWindowLevelForKey(.mainMenuWindow),
            CGWindowLevelForKey(.statusWindow),
            CGWindowLevelForKey(.popUpMenuWindow),
            CGWindowLevelForKey(.assistiveTechHighWindow),
            CGWindowLevelForKey(.screenSaverWindow),
        ]
        // OverlayWindow uses max + 1, so we use max + 2 to be above it
        let cursorLevel = levels.map { Int($0) }.max().map { $0 + 2 } ?? Int(CGWindowLevelForKey(.statusWindow)) + 2

        level = NSWindow.Level(rawValue: cursorLevel)
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
        guard animationDisplayLink == nil else { return }
        let animationDisplayLink = displayLink(
            target: self,
            selector: #selector(updateAnimation(_:))
        )
        self.animationDisplayLink = animationDisplayLink
        animationDisplayLink.add(to: .current, forMode: .common)
    }

    func stopAnimationLoop() {
        animationDisplayLink?.invalidate()
        animationDisplayLink = nil
    }

    @objc private func updateAnimation(_: CADisplayLink) {
        let manager = CursorHighlightManager.shared

        // Only call update functions for active features (or when transitioning to inactive to hide)
        let showingSpotlight = manager.shouldShowCursorHighlight
        if showingSpotlight || wasShowingSpotlight {
            highlightView.updateSpotlightPosition()
        }
        wasShowingSpotlight = showingSpotlight

        let showingRing = manager.shouldShowRing
        if showingRing || wasShowingRing {
            highlightView.updateHoldRingPosition()
        }
        wasShowingRing = showingRing

        let showingReleaseAnimation = manager.hasActiveAnimation
        if showingReleaseAnimation || wasShowingReleaseAnimation {
            highlightView.updateReleaseAnimation()
        }
        if showingReleaseAnimation {
            manager.cleanupExpiredAnimation()
        }
        wasShowingReleaseAnimation = showingReleaseAnimation

        let showingActiveCursor = manager.shouldShowActiveCursorOnAnyScreen()
        if showingActiveCursor || wasShowingActiveCursor {
            highlightView.updateActiveCursor()
        }
        wasShowingActiveCursor = showingActiveCursor

        if !manager.needsAnimationLoop {
            stopAnimationLoop()
        }
    }

    // MARK: - Visibility

    func updateVisibility() {
        let manager = CursorHighlightManager.shared

        // Apply the current show/hide state immediately. CADisplayLink may not
        // fire until the next click, so toggling spotlight off cannot wait for a frame.
        highlightView.updateSpotlightPosition()
        highlightView.updateHoldRingPosition()

        if manager.isActive || manager.cursorHighlightAvailable || manager.shouldShowActiveCursorOnAnyScreen() {
            orderFront(nil)
            startAnimationLoop()
        } else {
            orderOut(nil)
            stopAnimationLoop()
        }
    }
}
