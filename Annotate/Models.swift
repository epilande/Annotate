import Cocoa

/// Represents the available tools for annotation.
enum ToolType {
    case pen
    case arrow
    case line
    case highlighter
    case rectangle
    case circle
    case text
    case counter
    case select
    case eraser
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

/// Represents a timed point for pen/highlighter so we can do trailing fade-out
struct TimedPoint {
    var point: NSPoint
    var timestamp: CFTimeInterval
}

/// Represents a freehand drawing path.
struct DrawingPath {
    var points: [TimedPoint]
    var color: NSColor
    var lineWidth: CGFloat
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

/// Represents a rectangle annotation defined by two corner points.
struct Rectangle {
    var startPoint: NSPoint
    var endPoint: NSPoint
    var color: NSColor
    var lineWidth: CGFloat
    var creationTime: CFTimeInterval?
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
struct TextAnnotation {
    var text: String
    var position: NSPoint
    var color: NSColor
    var fontSize: CGFloat
}

struct CounterAnnotation {
    var number: Int
    var position: NSPoint
    var color: NSColor
    var creationTime: CFTimeInterval?
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
            && lhs.fontSize == rhs.fontSize
    }
}

extension CounterAnnotation: Equatable {
    public static func == (lhs: CounterAnnotation, rhs: CounterAnnotation) -> Bool {
        return lhs.number == rhs.number && lhs.position == rhs.position
            && lhs.color.isEqual(rhs.color) && lhs.creationTime == rhs.creationTime
    }
}
