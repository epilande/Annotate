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
    static let fadeDelayKey = "FadeDelay"
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
    static let defaultToolKey = "DefaultTool"
    static let lastUsedToolKey = "LastUsedTool"
}

let colorPalette: [NSColor] = [
    .systemRed, .systemOrange, .systemYellow,
    .systemGreen, .cyan, .systemIndigo,
    .magenta, .white, .black,
]

/// Seconds an annotation holds at full opacity before the fade-out begins
/// (fade mode only). The fade-out itself takes `OverlayView.fadeOutDuration`.
let defaultFadeDelay: Double = 0.5
let fadeDelayRange: ClosedRange<Double> = 0.25...5

let defaultTextAnnotationFontSize: CGFloat = 18
let textAnnotationFontSizeRange: ClosedRange<CGFloat> = 12...48

/// 14 pt reproduces counters' original 15 pt radius / 2.5 pt stroke; the badge
/// scales from here (see `CounterAnnotation.radius`).
let defaultCounterFontSize: CGFloat = 14
let counterFontSizeRange: ClosedRange<CGFloat> = 12...60

extension UserDefaults {
    var fadeDelay: TimeInterval {
        get {
            let stored = double(forKey: Self.fadeDelayKey)
            return stored > 0 ? stored : defaultFadeDelay
        }
        set {
            set(newValue, forKey: Self.fadeDelayKey)
        }
    }

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

    /// The tool to apply on overlay activation. Defaults to `.lastUsed`, which leaves the
    /// current in-memory tool untouched.
    var defaultToolOption: DefaultToolOption {
        get {
            let stored = string(forKey: Self.defaultToolKey) ?? ""
            return DefaultToolOption(rawValue: stored) ?? .lastUsed
        }
        set {
            set(newValue.rawValue, forKey: Self.defaultToolKey)
        }
    }

    /// The most recently explicitly selected tool, persisted so it survives app relaunches.
    var lastUsedTool: ToolType {
        get {
            let stored = string(forKey: Self.lastUsedToolKey) ?? ""
            return ToolType(rawValue: stored) ?? .pen
        }
        set {
            set(newValue.rawValue, forKey: Self.lastUsedToolKey)
        }
    }
}
