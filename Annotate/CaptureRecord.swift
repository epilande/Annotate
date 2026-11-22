import Foundation

/// The annotation data saved next to a capture's PNG when "Save annotation data next to
/// screenshots" is on: `Annotate 2026-11-01 at 10.23.45.json` beside
/// `Annotate 2026-11-01 at 10.23.45.png`.
///
/// This type is the file's schema, and `AnnotateTests/Fixtures/CaptureRecordV1.json` is a
/// complete example. It is a transfer format, separate from the live annotation structs, so
/// the app can change how it stores annotations without changing the file. Any change a
/// reader of version 1 couldn't handle raises `version`.
///
/// Conventions:
/// - Positions are in points, display-local, with the origin at the display's top-left corner
///   and y growing downward. `region` says where the image sits in that space, and the image
///   has `display.scale` pixels per point, so a point maps to image pixel
///   `((x - region.x) * scale, (y - region.y) * scale)`.
/// - Colors are sRGB hex: `#RRGGBB`, or `#RRGGBBAA` when not fully opaque. They are the color
///   the user picked. Highlighters draw at half that opacity, and a board shifts colors a
///   little toward its ink; the image shows the result.
/// - Times are seconds on the clock `clock` names. `hostTime` is the capture's reading of it
///   and `capturedAt` the wall time at that moment, so a reader can convert:
///   `wall(t) = capturedAt + (t - hostTime)`.
///
/// It lists what the image shows: annotations that fade had fully hidden, ones outside a Capture
/// Area region, and ones a newer redaction overlaps are left out.
struct CaptureRecord: Codable, Equatable, Sendable {
    /// What `format` always holds, so a reader can tell this file from other JSON.
    static let formatName = "annotate.capture"
    static let currentVersion = 1
    /// The clock every time in the record is on: `mach_absolute_time` in seconds, as
    /// `CACurrentMediaTime` reads it and ScreenCaptureKit stamps frames. It counts from boot
    /// and stops while the Mac sleeps.
    static let hostClock = "mach_absolute_time"

    var format = formatName
    var version = currentVersion
    /// ISO 8601 wall time of the capture, in UTC with milliseconds.
    var capturedAt: String
    /// The clock `hostTime` and every annotation time are read from; see `hostClock`.
    var clock = hostClock
    /// The capture's reading of `clock`, in seconds.
    var hostTime: Double
    var display: Display
    /// The area the image covers, in display points from the top-left.
    var region: Rect
    var image: Image
    /// The board drawn under the annotations, or absent when none was showing.
    var board: Board?
    /// Bottom to top: each annotation paints over the ones before it.
    var annotations: [Annotation]

    /// The display the capture was taken on.
    struct Display: Codable, Equatable, Sendable {
        /// The `CGDirectDisplayID`. It identifies the display while it stays connected, not
        /// across reboots.
        var id: UInt32
        /// Size in points.
        var width: Double
        var height: Double
        /// Pixels per point.
        var scale: Double
    }

    /// The PNG this record describes.
    struct Image: Codable, Equatable, Sendable {
        /// The PNG's file name, absent until the image is saved.
        var file: String?
        /// Size in pixels.
        var width: Int
        var height: Int
    }

    struct Board: Codable, Equatable, Sendable {
        /// `whiteboard` or `blackboard`.
        var style: String
        /// From 0.1 to 1. At 1 the board hides the screen entirely.
        var opacity: Double
    }

    struct Point: Codable, Equatable, Sendable {
        var x: Double
        var y: Double
    }

    /// `x` and `y` are the top-left corner.
    struct Rect: Codable, Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// One annotation. In JSON each is an object whose `kind` names the case, with the case's
    /// fields alongside it.
    enum Annotation: Equatable, Sendable {
        case pen(Stroke)
        case highlighter(Stroke)
        case arrow(Segment)
        case line(Segment)
        case rectangle(Shape)
        /// An ellipse inscribed in `rect`, drawn by the Oval tool.
        case ellipse(Shape)
        case redaction(Redaction)
        case text(Label)
        /// A numbered badge from the Counter tool.
        case pin(Pin)
    }

    /// A freehand line from the Pen or the Highlighter.
    struct Stroke: Codable, Equatable, Sendable {
        /// Stable while the annotation exists, across moves, edits, and undo. A copy pasted
        /// from it gets a new one.
        var id: String
        /// When the stroke was finished.
        var time: Double?
        var color: String
        /// Line width in points as drawn.
        var width: Double
        var points: [StrokePoint]
    }

    struct StrokePoint: Codable, Equatable, Sendable {
        var x: Double
        var y: Double
        /// When the pointer reached this point.
        var time: Double
    }

    /// An arrow from `start` with its head at `end`, or a plain line.
    struct Segment: Codable, Equatable, Sendable {
        var id: String
        var time: Double?
        var color: String
        /// Line width in points as drawn.
        var width: Double
        var start: Point
        var end: Point
    }

    /// An outlined rectangle or ellipse, or a filled one.
    struct Shape: Codable, Equatable, Sendable {
        var id: String
        var time: Double?
        var color: String
        /// Line width in points as drawn.
        var width: Double
        var rect: Rect
        /// `true` when filled with `color` rather than drawn as an outline, by the Filled Rectangle or
        /// Filled Oval tool. Absent for an outline, so outlines read as they did in version 1.
        var filled: Bool?
    }

    /// A rectangle that hides what is under it. The hidden pixels are never recorded.
    struct Redaction: Codable, Equatable, Sendable {
        var id: String
        var time: Double?
        /// `solid`, `pixelate`, or `blur`.
        var style: String
        var rect: Rect
    }

    /// A text label.
    struct Label: Codable, Equatable, Sendable {
        var id: String
        /// When the label was placed or last edited.
        var time: Double?
        var text: String
        var color: String
        var fontSize: Double
        /// Whether it draws on a rounded background pill, which extends 8 points left and
        /// right and 4 above and below `rect`.
        var background: Bool
        /// The text's lines, without the pill.
        var rect: Rect
    }

    /// A Counter badge: a circle of `radius` around `position` with `number` in it.
    struct Pin: Codable, Equatable, Sendable {
        var id: String
        var time: Double?
        var number: Int
        var position: Point
        var color: String
        var radius: Double
        /// `bordered` or `filled`.
        var style: String
    }

    /// The JSON written next to the image: pretty printed with sorted keys, so two records
    /// of the same capture are the same bytes.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// `date` as `capturedAt` writes it: `2026-11-01T18:23:45.123Z`.
    static func wallTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

extension CaptureRecord.Annotation: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
    }

    /// The `kind` each case writes.
    var kind: String {
        switch self {
        case .pen: "pen"
        case .highlighter: "highlighter"
        case .arrow: "arrow"
        case .line: "line"
        case .rectangle: "rectangle"
        case .ellipse: "ellipse"
        case .redaction: "redaction"
        case .text: "text"
        case .pin: "pin"
        }
    }

    /// The annotation's `id`, whatever its kind.
    var id: String {
        switch self {
        case .pen(let stroke), .highlighter(let stroke): stroke.id
        case .arrow(let segment), .line(let segment): segment.id
        case .rectangle(let shape), .ellipse(let shape): shape.id
        case .redaction(let redaction): redaction.id
        case .text(let label): label.id
        case .pin(let pin): pin.id
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        // The fields go in the same object as `kind`.
        switch self {
        case .pen(let stroke), .highlighter(let stroke): try stroke.encode(to: encoder)
        case .arrow(let segment), .line(let segment): try segment.encode(to: encoder)
        case .rectangle(let shape), .ellipse(let shape): try shape.encode(to: encoder)
        case .redaction(let redaction): try redaction.encode(to: encoder)
        case .text(let label): try label.encode(to: encoder)
        case .pin(let pin): try pin.encode(to: encoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "pen": self = .pen(try CaptureRecord.Stroke(from: decoder))
        case "highlighter": self = .highlighter(try CaptureRecord.Stroke(from: decoder))
        case "arrow": self = .arrow(try CaptureRecord.Segment(from: decoder))
        case "line": self = .line(try CaptureRecord.Segment(from: decoder))
        case "rectangle": self = .rectangle(try CaptureRecord.Shape(from: decoder))
        case "ellipse": self = .ellipse(try CaptureRecord.Shape(from: decoder))
        case "redaction": self = .redaction(try CaptureRecord.Redaction(from: decoder))
        case "text": self = .text(try CaptureRecord.Label(from: decoder))
        case "pin": self = .pin(try CaptureRecord.Pin(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "Unknown annotation kind \(kind)")
        }
    }
}
