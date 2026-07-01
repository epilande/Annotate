import Cocoa
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleOverlay = Self("toggleOverlay")
    static let toggleAlwaysOnMode = Self("toggleAlwaysOnMode")
}

extension UserDefaults {
    static let clearDrawingsOnStartKey = "ClearDrawingsOnStart"
    static let hideDockIconKey = "HideDockIcon"
    static let fadeModeKey = "FadeMode"
    static let enableBoardKey = "EnableBoard"
    static let boardOpacityKey = "BoardOpacity"
    static let alwaysOnModeKey = "AlwaysOnMode"
    static let lineWidthKey = "LineWidth"
    static let hideToolFeedbackKey = "HideToolFeedback"
    static let clickRippleEnabledKey = "ClickRippleEnabled"
    static let clickRippleColorKey = "ClickRippleColor"
    static let clickRippleSizeKey = "ClickRippleSize"
    static let cursorHighlightEnabledKey = "CursorHighlightEnabled"
    static let spotlightSizeKey = "SpotlightSize"
    static let activeCursorStyleKey = "ActiveCursorStyle"
    static let activeCursorSizeKey = "ActiveCursorSize"
    static let persistTextModeKey = "PersistTextMode"
    static let defaultTextFontSizeKey = "TextFontSize"
    static let defaultCounterFontSizeKey = "CounterFontSize"
}

let colorPalette: [NSColor] = [
    .systemRed, .systemOrange, .systemYellow,
    .systemGreen, .cyan, .systemIndigo,
    .magenta, .white, .black,
]

let defaultTextAnnotationFontSize: CGFloat = 18
let textAnnotationFontSizeRange: ClosedRange<CGFloat> = 12...48

/// 14 pt reproduces counters' original 15 pt radius / 2.5 pt stroke; the badge
/// scales from here (see `CounterAnnotation.radius`).
let defaultCounterFontSize: CGFloat = 14
let counterFontSizeRange: ClosedRange<CGFloat> = 12...60

extension UserDefaults {
    var textToolFontSize: CGFloat {
        get {
            let stored = double(forKey: Self.defaultTextFontSizeKey)
            return stored > 0 ? CGFloat(stored) : defaultTextAnnotationFontSize
        }
        set {
            set(Double(newValue), forKey: Self.defaultTextFontSizeKey)
        }
    }

    var counterToolFontSize: CGFloat {
        get {
            let stored = double(forKey: Self.defaultCounterFontSizeKey)
            return stored > 0 ? CGFloat(stored) : defaultCounterFontSize
        }
        set {
            set(Double(newValue), forKey: Self.defaultCounterFontSizeKey)
        }
    }
}
