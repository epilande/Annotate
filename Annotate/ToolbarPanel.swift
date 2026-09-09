import Cocoa
import SwiftUI

/// The floating toolbar lives in its own non-activating child panel of the overlay window.
/// A panel is what makes the bar draggable without any hand-rolled hit testing: AppKit moves
/// it for us through `isMovableByWindowBackground`. It never becomes key, so every keystroke
/// keeps going to the canvas, and it rides along with the overlay because a child window
/// follows its parent's ordering and its moves.
final class ToolbarPanel: NSPanel {
    /// Margin kept between the bar and the overlay edges, and the bar's default lift off the
    /// bottom. 20 pt is the resting place the bar has always had.
    static let edgeInset: CGFloat = 20
    /// Gap left between the bar and the quick picker when the two would otherwise overlap.
    static let pickerGap: CGFloat = 8

    private let host: ToolbarHostingView
    /// Measures the bar. `NSHostingView.fittingSize` measures `ViewThatFits` against an
    /// unbounded proposal, so the one-row layout always wins and is then clipped. A hosting
    /// controller proposes the width it is handed all the way down the view tree, which is the
    /// only way to learn which layout fits and how tall it is. It shares the model, so it
    /// always measures exactly what the bar is showing.
    private let measurer: NSHostingController<ToolbarView>
    /// The overlay this bar belongs to. Weak because the overlay owns the panel, not the reverse.
    private weak var overlay: OverlayWindow?
    /// True while the app, rather than the user, is moving the bar. Only a drag the user made
    /// is worth persisting, and the window server rounds a placed frame to whole points, so
    /// comparing frames afterwards is not a reliable way to tell the two apart.
    private var isPlacingProgrammatically = false
    /// The bar's offset from the overlay origin after the last placement. AppKit carries a
    /// child window along when its parent moves, preserving the offset, so a reported move that
    /// still matches this one is the overlay shifting rather than the user dragging the bar.
    private var lastKnownOffset: NSPoint?
    /// True between the mouse-down on the bar and the matching mouse-up. A drag reports a move
    /// per frame, so the writes are held back and folded into one at the end of the gesture.
    private var isUserDragging = false
    /// A move seen during a drag that still has to be written down when the drag ends.
    private var hasPendingSave = false

    init(overlay: OverlayWindow, model: ToolbarModel, perform: @escaping (ToolbarAction) -> Void) {
        self.overlay = overlay
        host = ToolbarHostingView(rootView: ToolbarView(model: model, perform: perform))
        measurer = NSHostingController(rootView: ToolbarView(model: model) { _ in })

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // The SwiftUI segments paint their own glass and shadow, so the panel itself is a
        // transparent, shadowless carrier.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isRestorable = false
        isReleasedWhenClosed = false
        // Match the overlay so the bar sits with it above everything and joins every Space.
        level = overlay.level
        collectionBehavior = overlay.collectionBehavior

        contentView = host

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    override var canBecomeKey: Bool { false }

    override var canBecomeMain: Bool { false }

    /// Marks the whole press as a user gesture, whichever way AppKit ends up moving the bar.
    /// `isMovableByWindowBackground` can swallow the press before `mouseDown` ever runs, and a
    /// native move like that reports a move per frame of the drag, so the flag has to be set
    /// here rather than in `mouseDown` alone or those frames would each be written down.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            isUserDragging = true
            super.sendEvent(event)
        case .leftMouseUp:
            super.sendEvent(event)
            endUserDrag()
        default:
            super.sendEvent(event)
        }
    }

    /// A press the SwiftUI chips did not consume falls through to the window, which is the
    /// signal that the user grabbed the bar itself. `isMovableByWindowBackground` covers this
    /// on its own for real drags, but a nonactivating panel in an inactive app does not always
    /// get that far, so start the drag explicitly.
    override func mouseDown(with event: NSEvent) {
        isUserDragging = true
        performDrag(with: event)
        // `performDrag` may swallow the whole gesture, mouse-up included, in which case
        // `sendEvent` never sees the end of it and this is the only place left to close it.
        // The button being back up is what tells the two apart: if it is still down the drag
        // is still running, so leave the gesture open for the mouse-up to close.
        guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
        endUserDrag()
    }

    /// Closes a user gesture and writes down the move it made, if it made one. A click that
    /// moved nothing leaves the pending flag clear, so it never records a position the user
    /// did not choose. Safe to call more than once for the same gesture.
    private func endUserDrag() {
        isUserDragging = false
        guard hasPendingSave else { return }
        hasPendingSave = false
        savePosition()
    }

    // MARK: - Attachment

    /// True while the bar is part of the overlay's window group, which is also the only state
    /// in which it can be on screen.
    var isAttached: Bool { parent != nil }

    /// Joins the overlay's window group and puts the bar back where the user left it. A detached
    /// bar is not carried along when the overlay moves or resizes, so its frame has gone stale by
    /// the time it is shown again and has to be rebuilt from the saved offset.
    func attach(to overlay: OverlayWindow) {
        guard parent == nil else { return }
        overlay.addChildWindow(self, ordered: .above)
        restoreSavedPosition()
    }

    func detach() {
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    func tearDown() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: self)
        detach()
        close()
    }

    // MARK: - Sizing and placement

    /// Measures the SwiftUI bar and resizes the panel around its bottom center. Holding the
    /// center rather than the origin keeps a centered bar centered when `ViewThatFits` swaps
    /// between the one-row and stacked layouts.
    func fitToContent() {
        guard let overlay else { return }
        // The width the bar may occupy. Proposing it is what lets `ViewThatFits` pick the
        // stacked layout on a narrow display instead of clipping the one-row bar.
        let available = max(0, overlay.frame.width - Self.edgeInset * 2)
        var size = measurer.sizeThatFits(
            in: CGSize(width: available, height: CGFloat.greatestFiniteMagnitude))
        size.width = min(size.width, available)
        guard size.width > 0, size.height > 0, size != frame.size else { return }

        let anchor = NSPoint(x: frame.midX, y: frame.minY)
        place(NSRect(origin: NSPoint(x: anchor.x - size.width / 2, y: anchor.y), size: size))
    }

    /// Runs the overlay's own frame change, then refreshes the bar around it. AppKit already
    /// carries a child window along with its parent, so only the width the bar may occupy and
    /// the clamp against the new frame need redoing. The move is bracketed so the bar being
    /// dragged along by its parent is never mistaken for the user parking it somewhere.
    ///
    /// A detached bar is not carried along, so its frame is a stale absolute position that is
    /// worth neither clamping nor recording as an offset. It is still measured, because its size
    /// has to be right before `attach` places it from the saved offset.
    func aroundOverlayFrameChange(_ body: () -> Void) {
        let wasPlacing = isPlacingProgrammatically
        isPlacingProgrammatically = true
        body()
        isPlacingProgrammatically = wasPlacing

        fitToContent()
        guard isAttached else { return }
        place(frame)
    }

    /// Puts the bar back where the user left it on this display, or at the default bottom
    /// center when nothing valid is stored.
    func restoreSavedPosition() {
        guard let overlay else { return }
        let origin: NSPoint
        if let offset = Self.savedOffset(for: overlay) {
            origin = NSPoint(x: overlay.frame.minX + offset.x, y: overlay.frame.minY + offset.y)
        } else {
            origin = NSPoint(
                x: overlay.frame.midX - frame.width / 2,
                y: overlay.frame.minY + Self.edgeInset
            )
        }
        place(NSRect(origin: origin, size: frame.size))
    }

    /// Keeps the bar fully inside the overlay it belongs to. AppKit consults this while the
    /// user drags a visible window; every programmatic placement runs it explicitly, because
    /// an off-screen window is never constrained.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let bounds = overlay?.frame else {
            return super.constrainFrameRect(frameRect, to: screen)
        }
        var rect = frameRect
        // Pin to the leading/bottom edge when the bar is larger than the overlay, so a bar that
        // cannot fit is clipped on the far side rather than dragged out of reach.
        rect.origin.x = max(bounds.minX, min(rect.origin.x, bounds.maxX - rect.width))
        rect.origin.y = max(bounds.minY, min(rect.origin.y, bounds.maxY - rect.height))
        return rect
    }

    private func place(_ rect: NSRect) {
        let wasPlacing = isPlacingProgrammatically
        isPlacingProgrammatically = true
        setFrame(constrainFrameRect(rect, to: nil), display: false)
        isPlacingProgrammatically = wasPlacing
        lastKnownOffset = currentOffset
    }

    private var currentOffset: NSPoint? {
        guard let overlay else { return nil }
        return NSPoint(x: frame.minX - overlay.frame.minX, y: frame.minY - overlay.frame.minY)
    }

    // MARK: - Persistence

    /// A move made during a user gesture only notes that there is something to save, because
    /// the end of the gesture writes it once rather than on every one of its 60-plus frames.
    /// Both drag paths are covered: `sendEvent` sees the press whether AppKit moves the bar
    /// itself or hands the drag to `mouseDown`. What is left to write immediately is a move
    /// with no gesture behind it, which is code placing the bar somewhere the user should
    /// find it again.
    @objc private func panelDidMove() {
        guard !isPlacingProgrammatically else { return }
        guard let offset = currentOffset, offset != lastKnownOffset else { return }
        lastKnownOffset = offset
        if isUserDragging {
            hasPendingSave = true
        } else {
            savePosition()
        }
    }

    /// Stores the bar's offset from the overlay origin, keyed by display. Absolute screen
    /// coordinates would not survive a resolution change or a display being unplugged, and
    /// `setFrameAutosaveName` would both store them and write to `UserDefaults.standard`
    /// instead of the suite the app was given.
    private func savePosition() {
        guard let defaults = Self.defaults,
            let overlay, let key = Self.displayKey(for: overlay)
        else { return }
        let offset = [
            Double(frame.minX - overlay.frame.minX),
            Double(frame.minY - overlay.frame.minY),
        ]
        var stored = defaults.dictionary(forKey: UserDefaults.toolbarPositionsKey) ?? [:]
        guard stored[key] as? [Double] != offset else { return }
        stored[key] = offset
        defaults.set(stored, forKey: UserDefaults.toolbarPositionsKey)
    }

    /// The suite the app was given, and nothing when there is no app behind the bar. A bar
    /// standing on its own (unit tests, previews) has no user whose position it could be
    /// remembering, so it must neither read nor rewrite the developer's own standard suite:
    /// falling back to it would let a real toolbar position leak into a test and would let a
    /// test write one back out. Same reasoning as `OverlayView.commitTextField`, which only
    /// broadcasts when the view belongs to a live overlay set.
    private static var defaults: UserDefaults? {
        AppDelegate.shared?.userDefaults
    }

    private static func savedOffset(for overlay: OverlayWindow) -> NSPoint? {
        guard let defaults,
            let key = displayKey(for: overlay),
            let stored = defaults.dictionary(forKey: UserDefaults.toolbarPositionsKey)?[key]
                as? [Double],
            stored.count == 2,
            stored.allSatisfy({ $0.isFinite })
        else { return nil }
        return NSPoint(x: stored[0], y: stored[1])
    }

    /// The display the overlay covers, as the stable number Core Graphics gives it. Read from
    /// the overlay and never from the panel: a bar dragged against an edge can report the
    /// neighboring display.
    static func displayKey(for overlay: OverlayWindow) -> String? {
        guard let screen = overlay.hostScreen,
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber
        else { return nil }
        return number.stringValue
    }
}

/// Hosts the SwiftUI bar. The panel is never key and the app is often inactive, so the first
/// click has to land on a chip rather than being spent activating anything.
final class ToolbarHostingView: NSHostingView<ToolbarView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
