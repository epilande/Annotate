import Cocoa

/// Represents the available tools for annotation.
enum ToolType: String, CaseIterable {
    case pen
    case arrow
    case line
    case highlighter
    case rectangle
    case circle
    case redact
    case text
    case counter
    case select
    case eraser

    var displayName: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .redact: return "Redact"
        case .text: return "Text"
        case .counter: return "Counter"
        case .eraser: return "Eraser"
        case .select: return "Select"
        }
    }

    /// The shortcut entry that selects this tool. Exhaustive so a new case cannot
    /// silently miss the overlay toolbar or the shortcut settings.
    var shortcutKey: ShortcutKey {
        switch self {
        case .pen: return .pen
        case .arrow: return .arrow
        case .line: return .line
        case .highlighter: return .highlighter
        case .rectangle: return .rectangle
        case .circle: return .circle
        case .redact: return .redact
        case .text: return .text
        case .counter: return .counter
        case .select: return .select
        case .eraser: return .eraser
        }
    }

    /// SF Symbol shown for this tool on the overlay toolbar.
    var symbolName: String {
        switch self {
        case .pen: return "pencil"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .highlighter: return "highlighter"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .redact: return "eye.slash"
        case .text: return "textformat"
        case .counter: return "number"
        case .select: return "cursorarrow"
        case .eraser: return "eraser"
        }
    }

    /// Rendered width per nominal point, keeping the highlighter's 14/3 ratio.
    /// Rendering, dirty-rect padding, selection and eraser hit-testing all read this,
    /// so the value must not be re-inlined at a call site.
    var strokeWidthMultiplier: CGFloat {
        self == .highlighter ? 4.67 : 1
    }

    /// Alpha ink is laid down at, applied at render time so the stored color is
    /// whatever the user picked. Same single-authority rule as the multiplier.
    var laydownAlpha: CGFloat {
        self == .highlighter ? 0.5 : 1
    }
}

/// Which tool becomes active each time the overlay is activated. `.lastUsed` keeps the
/// in-memory tool as-is (the pre-existing behavior); a specific tool always resets to it.
enum DefaultToolOption: RawRepresentable, Hashable {
    case lastUsed
    case tool(ToolType)

    var rawValue: String {
        switch self {
        case .lastUsed: return "lastUsed"
        case .tool(let tool): return tool.rawValue
        }
    }

    init?(rawValue: String) {
        if rawValue == "lastUsed" {
            self = .lastUsed
        } else if let tool = ToolType(rawValue: rawValue) {
            self = .tool(tool)
        } else {
            return nil
        }
    }
}

/// Represents a selected object for movement
enum SelectedObject: Equatable, Hashable {
    case path(index: Int)
    case arrow(index: Int)
    case line(index: Int)
    case highlight(index: Int)
    case rectangle(index: Int)
    case circle(index: Int)
    case text(index: Int)
    case counter(index: Int)
    case none

    /// Returns a tuple for sorting: (type priority, index)
    var sortValue: (Int, Int) {
        switch self {
        case .arrow(let idx): return (0, idx)
        case .line(let idx): return (1, idx)
        case .rectangle(let idx): return (2, idx)
        case .circle(let idx): return (3, idx)
        case .path(let idx): return (4, idx)
        case .highlight(let idx): return (5, idx)
        case .text(let idx): return (6, idx)
        case .counter(let idx): return (7, idx)
        case .none: return (99, 0)
        }
    }
}

/// The side handles on a single selected label. They only change the label's width: the
/// text rewraps, the height follows the content, and the font size stays where it is.
enum TextResizeHandle: CaseIterable, Hashable {
    case left, right
}

/// A freehand stroke point and the event time it was drawn at.
struct TimedPoint {
    var point: NSPoint
    var timestamp: CFTimeInterval
}

/// Represents a freehand drawing path.
struct DrawingPath {
    var points: [TimedPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var bezierPath: NSBezierPath? = nil
    var cachedBounds: NSRect = .null
    /// When the stroke was committed (pen up). Fade Mode holds and fades the whole stroke from
    /// this time, like every other annotation, rather than from its point timestamps.
    var creationTime: CFTimeInterval? = nil

    mutating func recacheBounds() {
        cachedBounds = DrawingPath.bounds(of: points)
    }

    mutating func expandCachedBounds(with point: NSPoint) {
        let pointRect = NSRect(origin: point, size: .zero)
        cachedBounds = cachedBounds.isNull ? pointRect : cachedBounds.union(pointRect)
    }

    static func bounds(of points: [TimedPoint]) -> NSRect {
        guard let first = points.first else { return .null }
        var bounds = NSRect(origin: first.point, size: .zero)
        for timedPoint in points.dropFirst() {
            bounds = bounds.union(NSRect(origin: timedPoint.point, size: .zero))
        }
        return bounds
    }
}

/// Represents an arrow annotation with start and end points.
struct Arrow {
    var startPoint: NSPoint
    var endPoint: NSPoint
    var color: NSColor
    var lineWidth: CGFloat
    var creationTime: CFTimeInterval?
}

/// Represents a line annotation with start and end points.
struct Line {
    var startPoint: NSPoint
    var endPoint: NSPoint
    var color: NSColor
    var lineWidth: CGFloat
    var creationTime: CFTimeInterval?
}

/// How a rectangle annotation is filled. `.outline` is the plain Rectangle tool; the
/// other three are the Redact tool's styles and hide whatever sits under the rectangle.
enum RectangleStyle: String, CaseIterable {
    case outline
    case solid
    case pixelate
    case blur

    var displayName: String {
        switch self {
        case .outline: return "Outline"
        case .solid: return "Solid"
        case .pixelate: return "Pixelate"
        case .blur: return "Blur"
        }
    }
}

/// Represents a rectangle annotation defined by two corner points.
struct Rectangle {
    var startPoint: NSPoint
    var endPoint: NSPoint
    var color: NSColor
    var lineWidth: CGFloat
    var creationTime: CFTimeInterval?
    var style: RectangleStyle = .outline
    /// Filtered screen pixels for `.pixelate` and `.blur`. Updated live while the rectangle
    /// is drawn or moved; whenever its key no longer matches the rectangle, it is retaken.
    /// Deliberately not part of `==`: the same annotation with or without its sample is
    /// the same annotation for undo, selection and clipboard purposes.
    var sample: RedactionSample? = nil

    /// Whether this rectangle hides content instead of outlining it.
    var isRedaction: Bool { style != .outline }

    /// Whether this rectangle needs captured screen pixels to render its style.
    var needsSample: Bool { style == .pixelate || style == .blur }

    /// The normalized bounds spanned by the two corner points.
    var bounds: NSRect {
        NSRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
    }
}

/// Represents a circular annotation defined by two corner points of its bounding box.
struct Circle {
    var startPoint: NSPoint
    var endPoint: NSPoint
    var color: NSColor
    var lineWidth: CGFloat
    var creationTime: CFTimeInterval?
}

/// Represents a text annotation.
/// Text laid out by TextKit, the line breaker the text field's editor uses. A label is
/// measured and drawn through this, and the editor is measured through it too, so a
/// committed label keeps exactly the lines the editor showed while typing.
///
/// `NSAttributedString.draw(with:options:context:)` can't stand in for it: it sometimes
/// breaks a line a word earlier than the editor and `boundingRect` do (seen where the
/// last line would hold a single word).
struct TextLayout {
    private let storage: NSTextStorage
    private let layoutManager = NSLayoutManager()
    private let container: NSTextContainer
    private let font: NSFont

    /// Lays out `text` with lines breaking at `width`, which is the text's own width. The
    /// editor's line fragment padding is part of the field's chrome instead.
    init(text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) {
        storage = NSTextStorage(string: text, attributes: attributes)
        font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
    }

    /// Size the lines occupy. The height is rounded up so the last line's descenders are
    /// never clipped, and empty text still takes up one line.
    var size: NSSize {
        let used = layoutManager.usedRect(for: container)
        let height = storage.length == 0 ? layoutManager.defaultLineHeight(for: font) : used.height
        return NSSize(width: used.width, height: ceil(height))
    }

    /// Draws the text hanging down from `topLeft` in the current unflipped context.
    func draw(topLeft: NSPoint) {
        guard let context = NSGraphicsContext.current else { return }
        NSGraphicsContext.saveGraphicsState()
        // TextKit lays lines out top down, so draw in a flipped context whose origin is the
        // text's top-left corner.
        let flip = NSAffineTransform()
        flip.translateX(by: topLeft.x, yBy: topLeft.y)
        flip.scaleX(by: 1, yBy: -1)
        flip.concat()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        layoutManager.drawGlyphs(forGlyphRange: layoutManager.glyphRange(for: container), at: .zero)
        NSGraphicsContext.restoreGraphicsState()
    }
}

struct TextAnnotation {
    var text: String
    var position: NSPoint
    var color: NSColor
    var fontSize: CGFloat
    var hasBackground: Bool = false
    /// Fixed text width from a Text-tool drag or a side handle. Lines wrap inside it and
    /// the box keeps this width even when the text is shorter. `nil` makes the label auto
    /// width: it grows with the text, up to `maxWidth`.
    var wrapWidth: CGFloat? = nil
    /// Widest an auto-width label may grow before it wraps, set when it is placed so it
    /// wraps at the screen edge instead of running off it. Ignored when `wrapWidth` is set.
    var maxWidth: CGFloat? = nil
    var creationTime: CFTimeInterval?
    /// Stable identity, so history can find this label again after deletes, undo and fade
    /// compaction have moved it within the array. Not part of equality: two labels that
    /// look the same are equal. A pasted copy gets a fresh one.
    var id = UUID()

    /// The narrowest a side handle can pull the box before the text has nowhere to go.
    static let minimumWrapWidth: CGFloat = 24

    /// Padding between the text and the edge of the background pill.
    static var pillInsets: NSEdgeInsets { NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8) }

    /// Corner radius of the background pill.
    static let pillCornerRadius: CGFloat = 6

    /// Opacity of the pill fill before any fade alpha is applied.
    static let pillFillAlpha: CGFloat = 0.85

    /// Bounds of the label for an already measured text size.
    ///
    /// With a background the insets are the pill's own padding, so the rect matches
    /// exactly what gets drawn. Without one the caller supplies its own slop, which
    /// keeps hit testing as forgiving as it was before pills existed.
    func bounds(textSize: NSSize, fallbackInsets: NSEdgeInsets) -> NSRect {
        let insets = hasBackground ? Self.pillInsets : fallbackInsets
        return NSRect(
            x: position.x - insets.left,
            y: position.y - insets.bottom,
            width: textSize.width + insets.left + insets.right,
            height: textSize.height + insets.top + insets.bottom
        )
    }

    /// Bounds of the label, measuring the text with the annotation's own font.
    ///
    /// Measures through `textSize()`, so the box grows taller as the text breaks into
    /// more lines.
    func bounds(fallbackInsets: NSEdgeInsets) -> NSRect {
        bounds(textSize: textSize(), fallbackInsets: fallbackInsets)
    }

    /// Width lines break at. Drawing lays the text out at this same width rather than the
    /// measured one, so a line that exactly fills the measured width never rewraps.
    var layoutWidth: CGFloat { wrapWidth ?? maxWidth ?? .greatestFiniteMagnitude }

    /// The text laid out at this annotation's font and `layoutWidth`, in `color`.
    func textLayout(color: NSColor? = nil) -> TextLayout {
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize)]
        attributes[.foregroundColor] = color
        return TextLayout(text: text, attributes: attributes, width: layoutWidth)
    }

    /// Measured text size at this annotation's font. Lines break at `wrapWidth` or
    /// `maxWidth` and at every line break in the text. Drawing uses the same layout, so
    /// the size is exactly what the drawn text occupies.
    func textSize() -> NSSize {
        let measured = textLayout().size
        return NSSize(width: wrapWidth ?? measured.width, height: measured.height)
    }

    /// Top edge of the text. `position` is the text's bottom-left, so this is what has to
    /// hold still for a label to grow downward.
    var textTop: CGFloat { position.y + textSize().height }

    /// Moves the label vertically so its text's top edge sits at `top`.
    mutating func pinTextTop(to top: CGFloat) {
        position.y = top - textSize().height
    }
}

/// How a counter badge paints its circle and number.
enum CounterStyle: String, CaseIterable {
    /// A circle stroked in the selected color, filled with a translucent contrasting color,
    /// with the number in the selected color.
    case bordered
    /// A borderless circle filled with the selected color, with a white number.
    case filled

    var displayName: String {
        switch self {
        case .bordered: return "Bordered"
        case .filled: return "Filled"
        }
    }
}

struct CounterAnnotation {
    var number: Int
    var position: NSPoint
    var color: NSColor
    var fontSize: CGFloat = defaultCounterFontSize
    var style: CounterStyle = .bordered
    var creationTime: CFTimeInterval?

    /// The badge circle radius, scaled from the number's font size so the
    /// original 15 pt radius is preserved at the default 14 pt font.
    var radius: CGFloat { fontSize * (15.0 / 14.0) }

    /// The badge circle stroke width, scaled from the number's font size so the
    /// original 2.5 pt stroke is preserved at the default 14 pt font.
    var strokeWidth: CGFloat { fontSize * (2.5 / 14.0) }

    /// The badge circle's bounding rect, centered on the counter's position.
    var badgeRect: NSRect {
        NSRect(
            x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)
    }
}

enum ClipboardItem {
    case arrow(Arrow)
    case line(Line)
    case path(DrawingPath)
    case highlight(DrawingPath)
    case rectangle(Rectangle)
    case circle(Circle)
    case text(TextAnnotation)
    case counter(CounterAnnotation)

    /// The copied object's creation time, which decides its layer against redactions.
    var creationTime: CFTimeInterval? {
        switch self {
        case .arrow(let arrow): return arrow.creationTime
        case .line(let line): return line.creationTime
        case .path(let path), .highlight(let path): return path.creationTime
        case .rectangle(let rectangle): return rectangle.creationTime
        case .circle(let circle): return circle.creationTime
        case .text(let text): return text.creationTime
        case .counter(let counter): return counter.creationTime
        }
    }
}

/// Describes actions that can be used for undo/redo operations.
enum DrawingAction {
    case addPath(DrawingPath)
    case addArrow(Arrow)
    case addLine(Line)
    case addHighlight(DrawingPath)
    case addRectangle(Rectangle)
    case addCircle(Circle)
    case addCounter(CounterAnnotation)
    case removePath(DrawingPath)
    case removeArrow(Arrow)
    case removeLine(Line)
    case removeHighlight(DrawingPath)
    case removeRectangle(Rectangle)
    case removeCircle(Circle)
    case removeCounter(CounterAnnotation)
    case addText(TextAnnotation)
    case removeText(TextAnnotation)
    case moveText(Int, NSPoint, NSPoint)
    case resizeText(TextAnnotation, TextAnnotation)  // from, to; the label is found by id
    case moveArrow(Int, NSPoint, NSPoint, NSPoint, NSPoint)  // index, fromStart, fromEnd, toStart, toEnd
    case moveLine(Int, NSPoint, NSPoint, NSPoint, NSPoint)
    case moveRectangle(Int, NSPoint, NSPoint, NSPoint, NSPoint)
    case moveCircle(Int, NSPoint, NSPoint, NSPoint, NSPoint)
    case movePath(Int, NSPoint)  // index, delta
    case moveHighlight(Int, NSPoint)  // index, delta
    case moveCounter(Int, NSPoint, NSPoint)  // index, from, to
    case clearAll(
        [DrawingPath], [Arrow], [Line], [DrawingPath], [Rectangle], [Circle], [TextAnnotation],
        [CounterAnnotation])
    case pasteObjects([SelectedObject])  // For undo: remove pasted objects
    case cutObjects([SelectedObject])  // For undo: restore cut objects
    case eraseAnnotations(
        [DrawingPath], [Arrow], [Line], [DrawingPath], [Rectangle], [Circle], [TextAnnotation],
        [CounterAnnotation])  // Stores all deleted items for undo
    case restoreAnnotations(
        [DrawingPath], [Arrow], [Line], [DrawingPath], [Rectangle], [Circle], [TextAnnotation],
        [CounterAnnotation])  // Reciprocal action for eraseAnnotations
}

// Add to Models.swift
extension TimedPoint: Equatable {
    public static func == (lhs: TimedPoint, rhs: TimedPoint) -> Bool {
        return lhs.point == rhs.point && lhs.timestamp == rhs.timestamp
    }
}

extension DrawingPath: Equatable {
    public static func == (lhs: DrawingPath, rhs: DrawingPath) -> Bool {
        return lhs.points == rhs.points && lhs.color.isEqual(rhs.color) && lhs.lineWidth == rhs.lineWidth
            && lhs.creationTime == rhs.creationTime
    }
}

extension Arrow: Equatable {
    public static func == (lhs: Arrow, rhs: Arrow) -> Bool {
        return lhs.startPoint == rhs.startPoint && lhs.endPoint == rhs.endPoint
            && lhs.color.isEqual(rhs.color) && lhs.lineWidth == rhs.lineWidth && lhs.creationTime == rhs.creationTime
    }
}

extension Line: Equatable {
    public static func == (lhs: Line, rhs: Line) -> Bool {
        return lhs.startPoint == rhs.startPoint && lhs.endPoint == rhs.endPoint
            && lhs.color.isEqual(rhs.color) && lhs.lineWidth == rhs.lineWidth && lhs.creationTime == rhs.creationTime
    }
}

extension Rectangle: Equatable {
    public static func == (lhs: Rectangle, rhs: Rectangle) -> Bool {
        return lhs.startPoint == rhs.startPoint && lhs.endPoint == rhs.endPoint
            && lhs.color.isEqual(rhs.color) && lhs.lineWidth == rhs.lineWidth && lhs.creationTime == rhs.creationTime
            && lhs.style == rhs.style
    }
}

extension Circle: Equatable {
    public static func == (lhs: Circle, rhs: Circle) -> Bool {
        return lhs.startPoint == rhs.startPoint && lhs.endPoint == rhs.endPoint
            && lhs.color.isEqual(rhs.color) && lhs.lineWidth == rhs.lineWidth && lhs.creationTime == rhs.creationTime
    }
}

extension TextAnnotation: Equatable {
    public static func == (lhs: TextAnnotation, rhs: TextAnnotation) -> Bool {
        return lhs.text == rhs.text && lhs.position == rhs.position && lhs.color.isEqual(rhs.color)
            && lhs.fontSize == rhs.fontSize && lhs.hasBackground == rhs.hasBackground
            && lhs.wrapWidth == rhs.wrapWidth && lhs.maxWidth == rhs.maxWidth
            && lhs.creationTime == rhs.creationTime
    }
}

extension CounterAnnotation: Equatable {
    public static func == (lhs: CounterAnnotation, rhs: CounterAnnotation) -> Bool {
        return lhs.number == rhs.number && lhs.position == rhs.position
            && lhs.color.isEqual(rhs.color) && lhs.fontSize == rhs.fontSize
            && lhs.style == rhs.style && lhs.creationTime == rhs.creationTime
    }
}
