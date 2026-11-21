import Cocoa

/// Paint bands, bottom to top. The renderer paints in this order, so moving a case moves
/// what it draws.
///
/// Every band except `selection` paints once per redaction layer (see
/// `OverlayDocument.RedactionLayer`): a covering shape (a redaction, solid rectangle or
/// solid circle) covers what was created before it, whatever the band, and sits under what
/// came after. `redactions`, which paints the covering shapes, therefore comes after every
/// content band, or a newer one would let older content show through.
/// `selection` is chrome with no creation time and paints once, over everything.
enum OverlayBand: Int, CaseIterable, Comparable {
    case strokes
    case shapes
    case text
    case redactions
    case selection

    static func < (lhs: OverlayBand, rhs: OverlayBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The kinds of annotation the content bands hold, in paint order within a band.
enum OverlayContent: CaseIterable {
    case arrows
    case lines
    case penStrokes
    case highlights
    case outlines
    case circles
    case labels
    case counters

    var band: OverlayBand {
        switch self {
        case .arrows, .lines, .penStrokes, .highlights: return .strokes
        case .outlines, .circles: return .shapes
        case .labels, .counters: return .text
        }
    }
}

/// One step of the paint order `OverlayDocument.paintOrder()` derives.
enum OverlayPaintStep: Equatable {
    /// The committed items of `content` created within `layer`. `includesLive` adds the
    /// item of that kind still being drawn, which is newer than everything committed.
    case content(OverlayContent, layer: OverlayDocument.RedactionLayer, includesLive: Bool)
    /// A committed covering shape, closing its layer.
    case cover(OverlayDocument.Cover)
    /// The covering shape still being drawn, if any, closing the top layer.
    case liveCover
    case selection
}

/// Everything the overlay draws that outlives a single gesture: the committed annotations,
/// the selection, and the label hidden while its text field edits it.
///
/// `OverlayView` owns one and redraws whenever it changes, so state written here can never
/// be left on screen stale. Live previews (the shape or stroke under the mouse) stay on the
/// view, which invalidates only the strip they touch.
struct OverlayDocument {
    var arrows: [Arrow] = []
    var lines: [Line] = []
    var paths: [DrawingPath] = []
    var highlightPaths: [DrawingPath] = []
    var rectangles: [Rectangle] = []
    var circles: [Circle] = []
    var textAnnotations: [TextAnnotation] = []
    var counterAnnotations: [CounterAnnotation] = []
    var nextCounterNumber: Int = 1

    /// Label whose text field is open; the field shows it, so the canvas skips it.
    var editingTextAnnotationIndex: Int?

    var selectedObjects: Set<SelectedObject> = []
    var selectionDragOffset: NSPoint?
    var selectionOriginalData: [SelectedObject: Any] = [:]
    var isDrawingSelectionRect: Bool = false
    var selectionRectStart: NSPoint?
    var selectionRectEnd: NSPoint?

    /// A shape that covers everything created before it and sits under everything after:
    /// a redaction, a solid rectangle, or a solid circle (`coversOlder`).
    enum Cover: Equatable, Hashable {
        case rectangle(index: Int)
        case circle(index: Int)
    }

    /// When `cover` was created.
    func creationTime(of cover: Cover) -> CFTimeInterval? {
        switch cover {
        case .rectangle(let index): return rectangles[index].creationTime
        case .circle(let index): return circles[index].creationTime
        }
    }

    /// Covering shapes from oldest to newest, which is the order they paint in. Ties keep
    /// rectangles before circles and each in array order.
    var coversByCreation: [Cover] {
        let covers =
            rectangles.indices.filter { rectangles[$0].coversOlder }.map { Cover.rectangle(index: $0) }
            + circles.indices.filter { circles[$0].coversOlder }.map { Cover.circle(index: $0) }
        return covers
            .enumerated()
            .sorted {
                let lhs = RedactionLayer.time(of: creationTime(of: $0.element))
                let rhs = RedactionLayer.time(of: creationTime(of: $1.element))
                return lhs != rhs ? lhs < rhs : $0.offset < $1.offset
            }
            .map(\.element)
    }

    /// A stretch of creation times between two consecutive covering shapes (see `Cover`; the
    /// name predates solid shapes). Everything created in `start..<end` paints over the
    /// covering shape made at `start` and under the one at `end`.
    struct RedactionLayer: Equatable {
        var start: CFTimeInterval = -.infinity
        var end: CFTimeInterval = .infinity

        /// Only test fixtures leave a committed object without a creation time; those
        /// count as the oldest.
        static func time(of creationTime: CFTimeInterval?) -> CFTimeInterval {
            creationTime ?? -.infinity
        }

        func contains(_ creationTime: CFTimeInterval?) -> Bool {
            let time = Self.time(of: creationTime)
            return time >= start && time < end
        }
    }

    /// Redaction indices from oldest to newest, which is the order they paint in.
    var redactionIndicesByCreation: [Int] {
        rectangles.indices.filter { rectangles[$0].isRedaction }.sorted {
            let lhs = RedactionLayer.time(of: rectangles[$0].creationTime)
            let rhs = RedactionLayer.time(of: rectangles[$1].creationTime)
            return lhs != rhs ? lhs < rhs : $0 < $1
        }
    }

    /// The order the renderer paints in, derived from `OverlayBand` and `OverlayContent`.
    func paintOrder() -> [OverlayPaintStep] {
        var steps: [OverlayPaintStep] = []
        func appendLayer(_ layer: RedactionLayer, closedBy redaction: OverlayPaintStep, isTop: Bool) {
            for band in OverlayBand.allCases where band != .selection {
                if band == .redactions {
                    steps.append(redaction)
                    continue
                }
                for content in OverlayContent.allCases where content.band == band {
                    steps.append(.content(content, layer: layer, includesLive: isTop))
                }
            }
        }

        var layer = RedactionLayer()
        for cover in coversByCreation {
            layer.end = RedactionLayer.time(of: creationTime(of: cover))
            appendLayer(layer, closedBy: .cover(cover), isTop: false)
            layer = RedactionLayer(start: layer.end)
        }
        appendLayer(layer, closedBy: .liveCover, isTop: true)
        steps.append(.selection)
        return steps
    }
}
