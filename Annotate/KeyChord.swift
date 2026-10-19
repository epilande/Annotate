import AppKit

/// A key press parsed once from an `NSEvent`. Shortcut matchers compare a chord against a
/// `ShortcutBinding` instead of reading `characters` or `charactersIgnoringModifiers` themselves.
///
/// AppKit translates a key through two layers of the active keyboard layout, and each shortcut
/// family matches on exactly one of them:
/// - `.base` (`charactersIgnoringModifiers`, Shift applied). Customizable bindings are recorded
///   and matched here, and so are the fixed selection and text commands. Option and Control
///   chords keep their letter (`characters` for Option+Command+T is "†"), and Shift
///   punctuation keeps its symbol (`characters` for Command+Shift+= is "=").
/// - `.command` (`characters` while Command is held). Command+W, Command+Z, Command+Shift+Z and
///   Command+R match here (#99). The Command layer carries QWERTY letters on Dvorak - QWERTY ⌘
///   and Latin letters on Russian, Greek and Hebrew, and falls back to the base letter on
///   layouts without one. The base layer misses those layouts and aliases unrelated chords:
///   on Dvorak - QWERTY ⌘ the base letter behind Command+, is "w".
struct KeyChord: Equatable {
    enum Layer {
        case base
        case command
    }

    let keyCode: UInt16
    /// The base-layer key, with keys that type nothing useful mapped by key code and the same
    /// normalization as `ShortcutBinding`.
    let key: String
    /// The Command-layer key, lowercased. `nil` unless Command is held.
    let commandKey: String?
    let modifiers: NSEvent.ModifierFlags
    /// The text the key types, for delivering it to an editor.
    let characters: String
    let isRepeat: Bool

    init?(event: NSEvent) {
        guard event.type == .keyDown || event.type == .keyUp else { return nil }
        let baseKey: String
        switch event.keyCode {
        case 49: baseKey = " "
        case 51, 117: baseKey = "\u{7f}" // Backspace and forward Delete share the overlay action.
        case 53: baseKey = "\u{1b}"
        case 36, 76: baseKey = "\r"
        case 48: baseKey = "\t"
        default: baseKey = event.charactersIgnoringModifiers ?? ""
        }
        let characters = event.characters ?? ""
        let modifiers = event.modifierFlags.intersection(ShortcutBinding.relevantModifiers)
        self.init(
            keyCode: event.keyCode,
            key: ShortcutBinding.normalizedKey(baseKey),
            commandKey: modifiers.contains(.command) ? characters.lowercased() : nil,
            modifiers: modifiers,
            characters: characters,
            isRepeat: event.isARepeat)
    }

    init(keyCode: UInt16, key: String, commandKey: String?, modifiers: NSEvent.ModifierFlags,
         characters: String, isRepeat: Bool) {
        self.keyCode = keyCode
        self.key = key
        self.commandKey = commandKey
        self.modifiers = modifiers
        self.characters = characters
        self.isRepeat = isRepeat
    }

    func key(on layer: Layer) -> String? {
        switch layer {
        case .base: return key
        case .command: return commandKey
        }
    }
}

extension ShortcutBinding {
    /// The binding a chord records: its base-layer key and exact modifiers.
    init?(chord: KeyChord) {
        guard chord.key.count == 1 else { return nil }
        self.init(chord.key, modifiers: chord.modifiers)
    }

    /// Matches when the chord's key on `layer` equals this binding's key and its modifiers equal
    /// this binding's modifiers once `ignoring` is removed. Customizable bindings use the
    /// defaults: base layer, exact modifiers. Unassigned bindings never match.
    func matches(_ chord: KeyChord, on layer: KeyChord.Layer = .base,
                 ignoring: NSEvent.ModifierFlags = []) -> Bool {
        guard !key.isEmpty, let chordKey = chord.key(on: layer), chordKey.count == 1 else { return false }
        return self == ShortcutBinding(chordKey, modifiers: chord.modifiers.subtracting(ignoring))
    }
}
