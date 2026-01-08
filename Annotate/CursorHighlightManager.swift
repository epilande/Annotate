import Cocoa

/// Cursor style options for active overlay indicator
enum ActiveCursorStyle: String, CaseIterable {
    case none = "none"
    case outline = "outline"
    case circle = "circle"
    case crosshair = "crosshair"

    var displayName: String {
        switch self {
        case .none: return "Default"
        case .outline: return "Outline"
        case .circle: return "Circle"
        case .crosshair: return "Crosshair"
        }
    }
}

/// Animation state when mouse is released - ring expands and fades
struct ReleaseAnimation {
    let center: NSPoint
    let startTime: CFTimeInterval
    let startSize: CGFloat
    let maxSize: CGFloat
    let duration: TimeInterval

    var isExpired: Bool {
        CACurrentMediaTime() - startTime >= duration
    }

    func progress(at time: CFTimeInterval = CACurrentMediaTime()) -> Double {
        let elapsed = time - startTime
        return min(elapsed / duration, 1.0)
    }
}

@MainActor
class CursorHighlightManager: @unchecked Sendable {
    static var shared = CursorHighlightManager()

    private let userDefaults: UserDefaults

    var cursorPosition: NSPoint = .zero
    var isMouseDown: Bool = false
    var mouseDownTime: CFTimeInterval = 0
    var releaseAnimation: ReleaseAnimation?

    let appearDuration: TimeInterval = 0.15
    let releaseDuration: TimeInterval = 0.2

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Click Effects Settings

    var clickEffectsEnabled: Bool {
        get { userDefaults.bool(forKey: UserDefaults.clickRippleEnabledKey) }
        set {
            userDefaults.set(newValue, forKey: UserDefaults.clickRippleEnabledKey)
            notifyStateChanged()
        }
    }

    var effectColor: NSColor {
        get {
            if let data = userDefaults.data(forKey: UserDefaults.clickRippleColorKey),
               let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
            {
                return color
            }
            return NSColor.systemYellow
        }
        set {
            if let data = try? NSKeyedArchiver.archivedData(
                withRootObject: newValue, requiringSecureCoding: true)
            {
                userDefaults.set(data, forKey: UserDefaults.clickRippleColorKey)
            }
            notifyStateChanged()
        }
    }

    var effectSize: CGFloat {
        get {
            let stored = userDefaults.double(forKey: UserDefaults.clickRippleSizeKey)
            return stored > 0 ? CGFloat(stored) : 70.0
        }
        set {
            userDefaults.set(Double(newValue), forKey: UserDefaults.clickRippleSizeKey)
            notifyStateChanged()
        }
    }

    var cursorHighlightEnabled: Bool {
        get { userDefaults.bool(forKey: UserDefaults.cursorHighlightEnabledKey) }
        set {
            userDefaults.set(newValue, forKey: UserDefaults.cursorHighlightEnabledKey)
            notifyStateChanged()
        }
    }

    var spotlightSize: CGFloat {
        get {
            let stored = userDefaults.double(forKey: UserDefaults.spotlightSizeKey)
            return stored > 0 ? CGFloat(stored) : 50.0
        }
        set {
            userDefaults.set(Double(newValue), forKey: UserDefaults.spotlightSizeKey)
            notifyStateChanged()
        }
    }

    // MARK: - Active Cursor Settings

    var activeCursorStyle: ActiveCursorStyle {
        get {
            let stored = userDefaults.string(forKey: UserDefaults.activeCursorStyleKey) ?? "none"
            return ActiveCursorStyle(rawValue: stored) ?? .none
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: UserDefaults.activeCursorStyleKey)
            notifyStateChanged()
        }
    }

    var activeCursorSize: CGFloat {
        get {
            let stored = userDefaults.double(forKey: UserDefaults.activeCursorSizeKey)
            return stored > 0 ? CGFloat(stored) : 14.0
        }
        set {
            userDefaults.set(Double(newValue), forKey: UserDefaults.activeCursorSizeKey)
            notifyStateChanged()
        }
    }

    /// Current annotation color (synced from AppDelegate)
    var annotationColor: NSColor = .systemRed {
        didSet {
            if oldValue != annotationColor {
                notifyStateChanged()
            }
        }
    }

    var holdRingStartSize: CGFloat { effectSize * 0.2 }
    var holdRingEndSize: CGFloat { effectSize * 0.65 }

    /// Animated ring size with ease-out curve
    var currentHoldRingSize: CGFloat {
        let elapsed = CACurrentMediaTime() - mouseDownTime
        let progress = min(elapsed / appearDuration, 1.0)
        let eased = 1.0 - pow(1.0 - progress, 3.0)
        return holdRingStartSize + (holdRingEndSize - holdRingStartSize) * eased
    }

    // MARK: - Computed State

    var isActive: Bool { clickEffectsEnabled }

    var shouldShowRing: Bool { isActive && isMouseDown }

    var shouldShowCursorHighlight: Bool {
        cursorHighlightEnabled && !isMouseDown
    }

    var hasActiveAnimation: Bool {
        releaseAnimation.map { !$0.isExpired } ?? false
    }

    // MARK: - Per-Screen Active Cursor
    // Active cursor visibility is determined per-screen based on actual overlay window visibility.
    // This allows multiple monitors to have independent overlay states.

    /// Called when overlay visibility changes to trigger cursor updates
    func overlayVisibilityChanged() {
        notifyStateChanged()
    }

    func isOverlayActiveOnScreen(_ screen: NSScreen) -> Bool {
        AppDelegate.shared?.overlayWindows[screen]?.isVisible ?? false
    }

    func shouldShowActiveCursorOnScreen(_ screen: NSScreen) -> Bool {
        isOverlayActiveOnScreen(screen) && activeCursorStyle != .none
    }

    func hasAnyActiveOverlay() -> Bool {
        AppDelegate.shared?.overlayWindows.values.contains { $0.isVisible } ?? false
    }

    /// Used to keep cursor highlight windows active when any overlay is visible
    func shouldShowActiveCursorOnAnyScreen() -> Bool {
        hasAnyActiveOverlay() && activeCursorStyle != .none
    }

    // MARK: - Release Animation

    func startReleaseAnimation() {
        guard isActive else { return }

        releaseAnimation = ReleaseAnimation(
            center: cursorPosition,
            startTime: CACurrentMediaTime(),
            startSize: currentHoldRingSize,
            maxSize: effectSize,
            duration: releaseDuration
        )
    }

    func cleanupExpiredAnimation() {
        if let animation = releaseAnimation, animation.isExpired {
            releaseAnimation = nil
        }
    }

    // MARK: - System Cursor Visibility

    private var isCursorHidden = false

    func hideSystemCursor() {
        guard !isCursorHidden else { return }
        NSCursor.hide()
        isCursorHidden = true
    }

    func showSystemCursor() {
        guard isCursorHidden else { return }
        NSCursor.unhide()
        isCursorHidden = false
    }

    func updateCursorVisibility() {
        // Find which screen the cursor is on
        guard let currentScreen = NSScreen.screens.first(where: {
            $0.frame.contains(cursorPosition)
        }) else {
            showSystemCursor()
            return
        }

        // Only hide system cursor if cursor is on a screen with active overlay
        if shouldShowActiveCursorOnScreen(currentScreen) {
            hideSystemCursor()
        } else {
            showSystemCursor()
        }
    }

    // MARK: - Notifications

    private func notifyStateChanged() {
        NotificationCenter.default.post(name: .cursorHighlightStateChanged, object: nil)
    }
}

extension Notification.Name {
    static let cursorHighlightStateChanged = Notification.Name("CursorHighlightStateChangedNotification")
    static let cursorHighlightNeedsUpdate = Notification.Name("CursorHighlightNeedsUpdateNotification")
}
