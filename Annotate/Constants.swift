import Cocoa
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleOverlay = Self("toggleOverlay")
    static let toggleAlwaysOnMode = Self("toggleAlwaysOnMode")
}

let colorPalette: [NSColor] = [
    .systemRed, .systemOrange, .systemYellow,
    .systemGreen, .cyan, .systemIndigo,
    .magenta, .white, .black,
]

/// Seconds an annotation stays at full opacity in Fade Mode before it starts to fade out.
/// The default is the hold Fade Mode has always used.
let defaultFadeDelay: TimeInterval = 0.625
let fadeDelayRange: ClosedRange<TimeInterval> = 0.25...5

/// Formats a fade delay for the Settings slider, e.g. "0.625s" or "2s".
func fadeDelayLabel(_ seconds: TimeInterval) -> String {
    String(format: "%gs", seconds)
}

let defaultTextAnnotationFontSize: CGFloat = 18
let textAnnotationFontSizeRange: ClosedRange<CGFloat> = 12...120

/// Matches the quick-picker stroke ladder (`QuickPickerView.widthOptions` max 24).
let lineWidthRange: ClosedRange<CGFloat> = 0.5...24

/// 14 pt reproduces counters' original 15 pt radius / 2.5 pt stroke; the badge
/// scales from here (see `CounterAnnotation.radius`).
let soundEffectVolume: Float = 0.2

let defaultCounterFontSize: CGFloat = 14
let counterFontSizeRange: ClosedRange<CGFloat> = 12...60
