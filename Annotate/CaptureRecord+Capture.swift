import AppKit

// Builds a `CaptureRecord` from a finished `Capture`. Reads only the capture: no app
// singletons and no views, so a later sink or a session recorder can make records the same way.

extension CaptureRecord {
    /// The record of `capture`. `imageFile` is the saved PNG's name, when there is one.
    /// `textSize` measures a label's text; tests pass a fixed size so the record doesn't
    /// depend on the system font's metrics.
    @MainActor
    init(
        _ capture: Capture,
        imageFile: String? = nil,
        textSize: (TextAnnotation) -> NSSize = { $0.textSize() }
    ) {
        let space = DisplaySpace(height: capture.display.frame.height)
        let display = capture.display
        self.init(
            capturedAt: Self.wallTime(capture.capturedAt),
            hostTime: capture.hostTime,
            display: Display(
                id: display.id,
                width: display.frame.width,
                height: display.frame.height,
                scale: display.scale),
            region: Rect(capture.region),
            image: Image(file: imageFile, width: capture.image.width, height: capture.image.height),
            board: capture.scene.flatMap(Self.board),
            annotations: capture.scene.map {
                Self.annotations(in: $0, region: space.viewRect(capture.region), space: space, textSize: textSize)
            } ?? [])
    }

    private static func board(of scene: CaptureScene) -> Board? {
        guard scene.board.isVisible else { return nil }
        let style =
            switch scene.board.type {
            case .whiteboard: "whiteboard"
            case .blackboard: "blackboard"
            }
        return Board(style: style, opacity: scene.boardOpacity)
    }

    /// The scene's annotations that show in `region`, in the order they paint. `region` is in
    /// the overlay view's points, bottom-left origin.
    @MainActor
    private static func annotations(
        in scene: CaptureScene, region: CGRect, space: DisplaySpace, textSize: (TextAnnotation) -> NSSize
    ) -> [Annotation] {
        let document = scene.document
        let redactions = document.rectangles.filter(\.isRedaction)
        let regionPath = CGPath(rect: region, transform: nil)
        /// Whether `ink`, the area an item paints, reaches the region: some of it is in the image.
        func reachesRegion(_ ink: CGPath) -> Bool {
            let box = ink.boundingBoxOfPath
            guard !box.isNull, box.intersects(region) else { return false }
            return region.contains(box) || ink.intersects(regionPath)
        }
        /// Whether a newer redaction than `time` covers any of `ink`. An item that only comes
        /// near a redaction stays.
        func isRedacted(_ ink: CGPath, createdAt time: CFTimeInterval?) -> Bool {
            let created = OverlayDocument.RedactionLayer.time(of: time)
            let box = ink.boundingBoxOfPath
            return redactions.contains {
                OverlayDocument.RedactionLayer.time(of: $0.creationTime) > created && $0.bounds.intersects(box)
                    && ink.intersects(CGPath(rect: $0.bounds, transform: nil))
            }
        }
        /// Whether fade has left the item made at `time` on screen. Outlined rectangles fade like
        /// everything else, so `alpha(creationTime:)` is `alpha(for:)` for them.
        func isVisible(_ time: CFTimeInterval?) -> Bool {
            scene.fade.alpha(creationTime: time, at: scene.now) != nil
        }
        /// The items of one kind that paint in `layer` and show in the image: not faded out,
        /// with ink in the region, and none of it under a newer redaction.
        func shown<Item>(
            _ items: [Item], in layer: OverlayDocument.RedactionLayer,
            time: (Item) -> CFTimeInterval?, ink: (Item) -> CGPath
        ) -> [Item] {
            items.filter { item in
                guard layer.contains(time(item)), isVisible(time(item)) else { return false }
                let drawn = ink(item)
                return reachesRegion(drawn) && !isRedacted(drawn, createdAt: time(item))
            }
        }

        var annotations: [Annotation] = []
        for step in document.paintOrder() {
            switch step {
            case let .content(content, layer, _):
                switch content {
                case .arrows:
                    annotations += shown(document.arrows, in: layer, time: \.creationTime, ink: \.ink)
                        .map { .arrow(Segment($0, space: space)) }
                case .lines:
                    annotations += shown(document.lines, in: layer, time: \.creationTime, ink: \.ink)
                        .map { .line(Segment($0, space: space)) }
                case .penStrokes:
                    annotations += shown(document.paths, in: layer, time: \.creationTime) { $0.ink(tool: .pen) }
                        .map { .pen(Stroke($0, tool: .pen, space: space)) }
                case .highlights:
                    annotations += shown(document.highlightPaths, in: layer, time: \.creationTime) {
                        $0.ink(tool: .highlighter)
                    }
                    .map { .highlighter(Stroke($0, tool: .highlighter, space: space)) }
                case .outlines:
                    let outlines = document.rectangles.filter { !$0.coversOlder }
                    annotations += shown(outlines, in: layer, time: \.creationTime, ink: \.ink)
                        .map { .rectangle(Shape($0, space: space)) }
                case .circles:
                    let outlines = document.circles.filter { !$0.coversOlder }
                    annotations += shown(outlines, in: layer, time: \.creationTime, ink: \.ink)
                        .map { .ellipse(Shape($0, space: space)) }
                case .labels:
                    for (index, label) in document.textAnnotations.enumerated()
                    where index != document.editingTextAnnotationIndex && layer.contains(label.creationTime)
                        && isVisible(label.creationTime) {
                        let size = textSize(label)
                        // In the image when its text is: the pill and hit-test slop don't count.
                        let text = CGPath(rect: NSRect(origin: label.position, size: size), transform: nil)
                        // Hidden when a newer redaction touches any of its box, pill and slop
                        // included, so none of its text can reappear here.
                        let box = label.bounds(textSize: size, fallbackInsets: AnnotationRenderer.plainLabelSlop)
                        let boxPath = CGPath(rect: box, transform: nil)
                        if reachesRegion(text), !isRedacted(boxPath, createdAt: label.creationTime) {
                            annotations.append(.text(Label(label, textSize: size, space: space)))
                        }
                    }
                case .counters:
                    annotations += shown(document.counterAnnotations, in: layer, time: \.creationTime, ink: \.ink)
                        .map { .pin(Pin($0, space: space)) }
                }
            case .cover(.rectangle(let index)):
                let rectangle = document.rectangles[index]
                if rectangle.isRedaction {
                    if reachesRegion(rectangle.ink) {
                        annotations.append(.redaction(Redaction(rectangle, space: space)))
                    }
                } else if isVisible(rectangle.creationTime), reachesRegion(rectangle.ink),
                    !isRedacted(rectangle.ink, createdAt: rectangle.creationTime) {
                    annotations.append(.rectangle(Shape(rectangle, space: space)))
                }
            case .cover(.circle(let index)):
                let circle = document.circles[index]
                if isVisible(circle.creationTime), reachesRegion(circle.ink),
                    !isRedacted(circle.ink, createdAt: circle.creationTime) {
                    annotations.append(.ellipse(Shape(circle, space: space)))
                }
            case .liveCover, .selection:
                // A capture has no live previews, and selection chrome is never in the image.
                break
            }
        }
        return annotations
    }
}

extension CaptureRecord {
    /// Converts the overlay view's points, which start at the display's bottom-left corner, to
    /// the record's, which start at its top-left.
    struct DisplaySpace {
        /// The display's height in points.
        var height: CGFloat

        func point(_ point: NSPoint) -> Point {
            Point(x: point.x, y: height - point.y)
        }

        func rect(_ rect: NSRect) -> Rect {
            Rect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        }

        /// A rect in the record's space, back in the view's.
        func viewRect(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        }
    }
}

extension CaptureRecord.Rect {
    /// A rect already in display points from the top-left.
    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

extension CaptureRecord.Stroke {
    init(_ path: DrawingPath, tool: ToolType, space: CaptureRecord.DisplaySpace) {
        self.init(
            id: path.id.uuidString,
            time: path.creationTime,
            color: CaptureRecord.hex(path.color),
            width: path.lineWidth * tool.strokeWidthMultiplier,
            points: path.points.map {
                let point = space.point($0.point)
                return CaptureRecord.StrokePoint(x: point.x, y: point.y, time: $0.timestamp)
            })
    }
}

extension CaptureRecord.Segment {
    init(_ arrow: Arrow, space: CaptureRecord.DisplaySpace) {
        self.init(
            id: arrow.id.uuidString,
            time: arrow.creationTime,
            color: CaptureRecord.hex(arrow.color),
            width: arrow.lineWidth,
            start: space.point(arrow.startPoint),
            end: space.point(arrow.endPoint))
    }

    init(_ line: Line, space: CaptureRecord.DisplaySpace) {
        self.init(
            id: line.id.uuidString,
            time: line.creationTime,
            color: CaptureRecord.hex(line.color),
            width: line.lineWidth,
            start: space.point(line.startPoint),
            end: space.point(line.endPoint))
    }
}

extension CaptureRecord.Shape {
    init(_ rectangle: Rectangle, space: CaptureRecord.DisplaySpace) {
        self.init(
            id: rectangle.id.uuidString,
            time: rectangle.creationTime,
            color: CaptureRecord.hex(rectangle.color),
            width: rectangle.lineWidth,
            rect: space.rect(rectangle.bounds),
            filled: rectangle.style == .filled ? true : nil)
    }

    init(_ circle: Circle, space: CaptureRecord.DisplaySpace) {
        let bounds = AnnotationRenderer.paddedBounds(circle.startPoint, circle.endPoint, padding: 0)
        self.init(
            id: circle.id.uuidString,
            time: circle.creationTime,
            color: CaptureRecord.hex(circle.color),
            width: circle.lineWidth,
            rect: space.rect(bounds),
            filled: circle.filled ? true : nil)
    }
}

extension CaptureRecord.Redaction {
    init(_ rectangle: Rectangle, space: CaptureRecord.DisplaySpace) {
        self.init(
            id: rectangle.id.uuidString,
            time: rectangle.creationTime,
            style: rectangle.style.rawValue,
            rect: space.rect(rectangle.bounds))
    }
}

extension CaptureRecord.Label {
    /// `position` is the text's bottom-left corner, so the top edge comes from `textSize`.
    init(_ label: TextAnnotation, textSize: NSSize, space: CaptureRecord.DisplaySpace) {
        self.init(
            id: label.id.uuidString,
            time: label.creationTime,
            text: label.text,
            color: CaptureRecord.hex(label.color),
            fontSize: label.fontSize,
            background: label.hasBackground,
            rect: space.rect(NSRect(origin: label.position, size: textSize)))
    }
}

extension CaptureRecord.Pin {
    init(_ counter: CounterAnnotation, space: CaptureRecord.DisplaySpace) {
        self.init(
            id: counter.id.uuidString,
            time: counter.creationTime,
            number: counter.number,
            position: space.point(counter.position),
            color: CaptureRecord.hex(counter.color),
            radius: counter.radius,
            style: counter.style.rawValue)
    }
}

extension CaptureRecord {
    /// `color` in sRGB as `#RRGGBB`, or `#RRGGBBAA` when it isn't opaque. Components outside
    /// sRGB clamp to its edge. A color with no sRGB form, such as a pattern, reads as black.
    static func hex(_ color: NSColor) -> String {
        guard let srgb = color.usingColorSpace(.sRGB) else { return "#000000" }
        func byte(_ component: CGFloat) -> Int {
            Int((min(max(component, 0), 1) * 255).rounded())
        }
        let rgb = String(
            format: "#%02X%02X%02X", byte(srgb.redComponent), byte(srgb.greenComponent), byte(srgb.blueComponent))
        let alpha = byte(srgb.alphaComponent)
        return alpha == 255 ? rgb : rgb + String(format: "%02X", alpha)
    }
}
