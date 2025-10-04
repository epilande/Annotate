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
    case clearAll(
        [DrawingPath], [Arrow], [Line], [DrawingPath], [Rectangle], [Circle], [TextAnnotation],
        [CounterAnnotation])
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
