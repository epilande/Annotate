import Cocoa

/// Focused-editor chrome for in-place text annotations.
///
/// AppKit's shared field editor follows the window appearance, so in Dark Mode it
/// paints a dark fill even when `NSTextField.backgroundColor` is light. Black
/// annotation text then disappears while typing, then reappears after commit.
///
/// Contrast is derived from the (board-adapted) annotation color: dark text gets
/// a light editor, light text gets a dark editor. Committed drawing still uses
/// the annotation's own color; this type only styles the live editor.
enum AnnotationTextEditorContrast {
    static func usesLightEditor(for textColor: NSColor) -> Bool {
        textColor.contrastingColor() == .white
    }

    static func backgroundColor(for textColor: NSColor) -> NSColor {
        let fill = textColor.contrastingColor()
        let alpha: CGFloat = usesLightEditor(for: textColor) ? 0.92 : 0.85
        return fill.withAlphaComponent(alpha)
    }

    static func appearance(for textColor: NSColor) -> NSAppearance {
        let name: NSAppearance.Name = usesLightEditor(for: textColor) ? .aqua : .darkAqua
        return NSAppearance(named: name) ?? .currentDrawing()
    }

    static func apply(to textField: NSTextField, textColor: NSColor) {
        textField.textColor = textColor
        textField.cell?.textColor = textColor
        textField.drawsBackground = true
        textField.backgroundColor = backgroundColor(for: textColor)
        textField.appearance = appearance(for: textColor)
        if textField.wantsLayer {
            textField.layer?.backgroundColor = backgroundColor(for: textColor).cgColor
        }
    }

    static func apply(to editor: NSText, textColor: NSColor) {
        editor.appearance = appearance(for: textColor)
        editor.textColor = textColor
        editor.drawsBackground = true
        editor.backgroundColor = backgroundColor(for: textColor)
        guard let textView = editor as? NSTextView else { return }
        textView.insertionPointColor = textColor
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor,
            .foregroundColor: textColor,
        ]
    }
}
