import Cocoa
import SwiftUI

/// A persisted setting: the `UserDefaults` key it lives under, the value to use when nothing
/// usable is stored, and how the value is encoded. Keys are only declared in this file, so the
/// stored key strings and encodings below are the whole on-disk contract. Renaming a key string
/// or changing an encoding silently resets that setting for every existing user.
struct SettingKey<Value> {
    let name: String
    let defaultValue: Value
    /// Returns nil when the stored value is missing or unusable, which falls back to the default.
    fileprivate let decode: (UserDefaults, String) -> Value?
    /// Returns nil when the value cannot be encoded, which leaves the stored value untouched.
    fileprivate let encode: (Value) -> Any?
}

/// The single place the app reads and writes `UserDefaults`. Wraps an injected suite so tests
/// run against `TestUserDefaults` instead of the developer's own preferences.
struct SettingsStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static var standard: SettingsStore { SettingsStore(defaults: .standard) }

    /// Accessibility preferences owned by macOS, read-only.
    static var universalAccess: SettingsStore? {
        UserDefaults(suiteName: "com.apple.universalaccess").map(SettingsStore.init(defaults:))
    }

    subscript<Value>(key: SettingKey<Value>) -> Value {
        get { key.decode(defaults, key.name) ?? key.defaultValue }
        nonmutating set {
            guard let encoded = key.encode(newValue) else { return }
            defaults.set(encoded, forKey: key.name)
        }
    }

    func hasValue<Value>(for key: SettingKey<Value>) -> Bool {
        defaults.object(forKey: key.name) != nil
    }

    func removeValue<Value>(for key: SettingKey<Value>) {
        defaults.removeObject(forKey: key.name)
    }
}

// MARK: - Keys

extension SettingKey<Bool> {
    static var clearDrawingsOnStart: Self { .bool("ClearDrawingsOnStart") }
    static var hideDockIcon: Self { .bool("HideDockIcon") }
    static var hideToolFeedback: Self { .bool("HideToolFeedback") }
    static var fadeMode: Self { .bool("FadeMode", default: true, acceptsText: false) }
    static var alwaysOnMode: Self { .bool("AlwaysOnMode") }
    static var toolbarVisible: Self { .bool("ToolbarVisible", default: true, acceptsText: false) }
    static var soundsEnabled: Self { .bool("SoundsEnabled") }
    static var enableBoard: Self { .bool("EnableBoard") }

    static var textBackground: Self { .bool("TextBackgroundOn") }
    /// Whether committing a label switches to the Select tool with that label selected.
    /// Off by default so text mode stays sticky.
    static var selectAfterPlacingText: Self { .bool("SelectAfterPlacingText") }

    static var clickRippleEnabled: Self { .bool("ClickRippleEnabled") }
    static var cursorHighlightEnabled: Self { .bool("CursorHighlightEnabled") }
    static var spotlightRequiresOverlay: Self { .bool("SpotlightRequiresOverlay") }
    static var spotlightDimmingEnabled: Self { .bool("SpotlightDimmingEnabled") }
    static var spotlightAutoDim: Self { .bool("SpotlightAutoDim") }
}

extension SettingKey<Double> {
    /// A stored 0 reads as unset, and anything else is clamped to the slider's range.
    static var boardOpacity: Self {
        .double("BoardOpacity", default: 0.9) { $0 == 0 ? nil : $0.clamped(to: 0.1...1.0) }
    }
    /// Seconds annotations hold at full opacity in Fade Mode. A stored 0 or less reads as
    /// unset, and anything else is clamped to the slider's range.
    static var fadeDelay: Self {
        .double("FadeDelay", default: defaultFadeDelay) { $0 > 0 ? $0.clamped(to: fadeDelayRange) : nil }
    }
}

extension SettingKey<CGFloat> {
    static var lineWidth: Self { .cgFloat("LineWidth", default: 3.0, acceptsText: false) }
    static var textFontSize: Self { .cgFloat("TextFontSize", default: defaultTextAnnotationFontSize, positive: true) }
    static var counterFontSize: Self { .cgFloat("CounterFontSize", default: defaultCounterFontSize, positive: true) }

    static var clickRippleSize: Self { .cgFloat("ClickRippleSize", default: 70, positive: true) }
    static var spotlightSize: Self { .cgFloat("SpotlightSize", default: 50, positive: true) }
    /// How dark the dimmed background gets, 0-1.
    static var spotlightDimmingOpacity: Self { .cgFloat("SpotlightDimmingOpacity", default: 0.5, positive: true) }
    static var activeCursorSize: Self { .cgFloat("ActiveCursorSize", default: 14, positive: true) }

    /// System cursor scale from Accessibility settings (1.0 = default, up to 4.0 = max). Read
    /// through `SettingsStore.universalAccess`; stored as a Float by macOS.
    static var systemCursorScale: Self {
        SettingKey(
            name: "mouseDriverCursorSize", defaultValue: 1,
            decode: { defaults, name in
                guard let scale = defaults.storedDouble(forKey: name) else { return nil }
                return scale > 0 ? CGFloat(Float(scale)) : nil
            },
            encode: { Float($0) })
    }
}

extension SettingKey<SoundTheme> {
    /// Falls back to `.chalk` when the stored theme is one the app no longer ships.
    static var soundTheme: Self { .rawValue("SoundTheme", default: .chalk) }
}

extension SettingKey<ToolType> {
    /// The most recently explicitly selected tool, so it survives app relaunches.
    static var lastUsedTool: Self { .rawValue("LastUsedTool", default: .pen) }
}

extension SettingKey<DefaultToolOption> {
    /// The tool to apply on overlay activation. `.lastUsed` leaves the current tool untouched.
    static var defaultTool: Self { .rawValue("DefaultTool", default: .lastUsed) }
}

extension SettingKey<RectangleStyle> {
    /// The fill the Redact tool gives new rectangles. Never `.outline`: a stored outline falls
    /// back to the solid default so a redaction always hides.
    static var redactionStyle: Self { .rawValue("RedactionStyle", default: .solid) { $0 != .outline } }
}

extension SettingKey<CounterStyle> {
    /// The look the Counter tool gives new badges. Existing badges keep the style they were
    /// placed with.
    static var counterStyle: Self { .rawValue("CounterStyle", default: .bordered) }
}

extension SettingKey<ActiveCursorStyle> {
    static var activeCursorStyle: Self { .rawValue("ActiveCursorStyle", default: .none) }
}

extension SettingKey<NSColor> {
    static var selectedColor: Self { .archivedColor("SelectedColor", default: .systemRed) }
    static var clickRippleColor: Self { .archivedColor("ClickRippleColor", default: .systemYellow) }
}

extension SettingKey<[String]> {
    /// Bundle identifiers of apps where cursor effects are suppressed.
    static var hideCursorEffectsInApps: Self {
        SettingKey(
            name: "HideCursorEffectsInApps", defaultValue: [],
            decode: { defaults, name in defaults.stringArray(forKey: name) },
            encode: { $0 })
    }
}

extension SettingKey<[String: [Double]]> {
    /// Where the user parked the floating toolbar, per display: display number to the bar's
    /// [x, y] offset from its overlay window's origin.
    static var toolbarPositions: Self {
        SettingKey(
            name: "ToolbarPositions", defaultValue: [:],
            decode: { defaults, name in
                defaults.dictionary(forKey: name)?.compactMapValues { $0 as? [Double] }
            },
            encode: { $0 })
    }
}

extension SettingKey<ShortcutBinding> {
    /// An overlay shortcut. Stored as `["key": String, "modifiers": UInt]`, except unassigned,
    /// which is stored as `""`. Versions before modifier support stored the bare key string,
    /// which still reads back as a binding without modifiers.
    static func shortcut(_ action: ShortcutKey) -> Self {
        SettingKey(
            name: "shortcut." + action.rawValue, defaultValue: action.defaultBinding,
            decode: { defaults, name in
                if let legacyKey = defaults.string(forKey: name) {
                    return ShortcutBinding(legacyKey)
                }
                guard let value = defaults.dictionary(forKey: name),
                    let key = value["key"] as? String,
                    let modifiers = (value["modifiers"] as? NSNumber)?.uintValue
                else { return nil }
                return ShortcutBinding(key, modifiers: NSEvent.ModifierFlags(rawValue: modifiers))
            },
            encode: { binding in
                binding.key.isEmpty ? "" : ["key": binding.key, "modifiers": binding.modifiers.rawValue]
            })
    }
}

// MARK: - Encodings

/// Typed reads that return nil when the stored value has the wrong type, so it falls back to
/// the key's default. `bool(forKey:)` and `double(forKey:)` would read it as false or 0.
/// `acceptsText: false` is for keys that read with an `as?` cast before the store, so a string
/// stored there has always read as the default.
private extension UserDefaults {
    /// Accepts a number. With `acceptsText`, also a string `bool(forKey:)` understands ("YES",
    /// "true", "1"), so a value set with `defaults write` but without `-bool` still reads.
    func storedBool(forKey name: String, acceptsText: Bool) -> Bool? {
        switch object(forKey: name) {
        case let number as NSNumber:
            return number.boolValue
        case let string as String where acceptsText:
            switch string.lowercased() {
            case "yes", "true": return true
            case "no", "false": return false
            default: return Int(string).map { $0 != 0 }
            }
        default:
            return nil
        }
    }

    /// Accepts a number. With `acceptsText`, also a string that parses as one.
    func storedDouble(forKey name: String, acceptsText: Bool = true) -> Double? {
        switch object(forKey: name) {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String where acceptsText:
            return Double(string)
        default:
            return nil
        }
    }
}

private extension SettingKey where Value == Bool {
    static func bool(_ name: String, default defaultValue: Bool = false, acceptsText: Bool = true) -> Self {
        SettingKey(
            name: name, defaultValue: defaultValue,
            decode: { defaults, name in defaults.storedBool(forKey: name, acceptsText: acceptsText) },
            encode: { $0 })
    }
}

private extension SettingKey where Value == Double {
    static func double(
        _ name: String, default defaultValue: Double, normalize: @escaping (Double) -> Double? = { $0 }
    ) -> Self {
        SettingKey(
            name: name, defaultValue: defaultValue,
            decode: { defaults, name in defaults.storedDouble(forKey: name).flatMap(normalize) },
            encode: { $0 })
    }
}

private extension SettingKey where Value == CGFloat {
    /// Stored as a Double. With `positive`, a stored value of 0 or less reads as unset.
    static func cgFloat(
        _ name: String, default defaultValue: CGFloat, positive: Bool = false, acceptsText: Bool = true
    ) -> Self {
        SettingKey(
            name: name, defaultValue: defaultValue,
            decode: { defaults, name in
                guard let stored = defaults.storedDouble(forKey: name, acceptsText: acceptsText) else { return nil }
                return !positive || stored > 0 ? CGFloat(stored) : nil
            },
            encode: { Double($0) })
    }
}

private extension SettingKey where Value: RawRepresentable, Value.RawValue == String {
    /// Stored as the raw string. Unknown raw values, and any `isAllowed` rejects, read as unset.
    static func rawValue(
        _ name: String, default defaultValue: Value, isAllowed: @escaping (Value) -> Bool = { _ in true }
    ) -> Self {
        SettingKey(
            name: name, defaultValue: defaultValue,
            decode: { defaults, name in
                defaults.string(forKey: name).flatMap(Value.init(rawValue:)).flatMap { isAllowed($0) ? $0 : nil }
            },
            encode: { $0.rawValue })
    }
}

private extension SettingKey where Value == NSColor {
    /// Stored as `NSKeyedArchiver` data.
    static func archivedColor(_ name: String, default defaultValue: NSColor) -> Self {
        SettingKey(
            name: name, defaultValue: defaultValue,
            decode: { defaults, name in
                defaults.data(forKey: name).flatMap {
                    try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: $0)
                }
            },
            encode: { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) })
    }
}

// MARK: - SwiftUI

/// `@AppStorage` bindings that take their key string and default from a `SettingKey`, so a
/// Settings pane can't drift from the store. They read the raw stored value, without the
/// key's fallback rules.
extension AppStorage where Value == Bool {
    init(_ key: SettingKey<Bool>, store: UserDefaults? = nil) {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }
}

extension AppStorage where Value == Double {
    init(_ key: SettingKey<Double>, store: UserDefaults? = nil) {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }

    init(_ key: SettingKey<CGFloat>, store: UserDefaults? = nil) {
        self.init(wrappedValue: Double(key.defaultValue), key.name, store: store)
    }
}

extension AppStorage where Value: RawRepresentable, Value.RawValue == String {
    init(_ key: SettingKey<Value>, store: UserDefaults? = nil) {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }
}
