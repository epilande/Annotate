import Cocoa
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleOverlay = Self("toggleOverlay")
    static let toggleAlwaysOnMode = Self("toggleAlwaysOnMode")
}

/// The annotation colors offered by the color picker, in picker order. The raw value names the
/// color in Shortcuts actions and commands, so renaming a case breaks saved shortcuts.
enum PaletteColor: String, CaseIterable, Sendable {
    case red, orange, yellow
    case green, cyan, indigo
    case magenta, white, black

    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .cyan: return .cyan
        case .indigo: return .systemIndigo
        case .magenta: return .magenta
        case .white: return .white
        case .black: return .black
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

let colorPalette: [NSColor] = PaletteColor.allCases.map(\.nsColor)

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
