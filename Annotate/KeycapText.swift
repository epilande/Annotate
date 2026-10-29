import SwiftUI

extension Text {
    /// A shortcut's `displayValue` as keycap text. The ␣ character sits on the baseline at
    /// keycap sizes and nearly disappears, so it is drawn as the `space` symbol, which has
    /// the same shape and is sized and centered like the letters around it.
    init(keycap displayValue: String) {
        let parts = displayValue.components(separatedBy: ShortcutBinding.spaceGlyph)
        var text = Text(verbatim: parts[0])
        for part in parts.dropFirst() {
            text = Text("\(text)\(Image(systemName: "space"))\(Text(verbatim: part))")
        }
        self = text
    }
}
