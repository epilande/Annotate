import Cocoa

/// Cursor style options for active overlay indicator
enum ActiveCursorStyle: String, CaseIterable {
    case none = "none"
    case outline = "outline"
    case dot = "dot"
    case crosshair = "crosshair"

    var displayName: String {
        switch self {
        case .none: return "Default"
        case .outline: return "Outline"
        case .dot: return "Dot"
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
            let oldValue = activeCursorStyle
            userDefaults.set(newValue.rawValue, forKey: UserDefaults.activeCursorStyleKey)
            notifyStateChanged()
            updateSystemCursorVisibility(oldStyle: oldValue, newStyle: newValue)
        }
    }

    /// Whether the annotation overlay is currently active/visible
    var isOverlayActive: Bool = false {
        didSet {
            if oldValue != isOverlayActive {
                notifyStateChanged()
                updateSystemCursorVisibility(wasActive: oldValue, isActive: isOverlayActive)
            }
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

    var shouldShowActiveCursor: Bool {
        isOverlayActive && activeCursorStyle != .none
    }

    var hasActiveAnimation: Bool {
        releaseAnimation.map { !$0.isExpired } ?? false
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

    private var isSystemCursorHidden = false

    private func updateSystemCursorVisibility(wasActive: Bool, isActive: Bool) {
        let shouldHide = isActive && activeCursorStyle != .none
        let wasHidden = wasActive && activeCursorStyle != .none

        if shouldHide && !wasHidden {
            hideSystemCursor()
        } else if !shouldHide && wasHidden {
            showSystemCursor()
        }
    }

    private func updateSystemCursorVisibility(oldStyle: ActiveCursorStyle, newStyle: ActiveCursorStyle) {
        guard isOverlayActive else { return }

        let shouldHide = newStyle != .none
        let wasHidden = oldStyle != .none

        if shouldHide && !wasHidden {
            hideSystemCursor()
        } else if !shouldHide && wasHidden {
            showSystemCursor()
        }
    }

    private func hideSystemCursor() {
        guard !isSystemCursorHidden else { return }
        NSCursor.hide()
        isSystemCursorHidden = true
    }

    private func showSystemCursor() {
        guard isSystemCursorHidden else { return }
        NSCursor.unhide()
        isSystemCursorHidden = false
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
