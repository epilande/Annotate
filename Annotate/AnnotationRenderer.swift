import Cocoa

/// How strongly annotations draw at a given moment.
///
/// In Fade Mode an annotation holds at full strength for `delay`, then eases out over
/// `outDuration`. In Persist everything is at full strength, except that annotations caught
/// mid-fade by a switch to Persist ease back over `persistRestoreDuration` from
/// `persistRestoreStart`.
struct FadePolicy: Equatable {
    var isFadeMode: Bool
    var delay: CFTimeInterval
    var outDuration: CFTimeInterval
    /// When Persist began easing dimmed annotations back, or nil when nothing was dimmed.
    var persistRestoreStart: CFTimeInterval?
    var persistRestoreDuration: CFTimeInterval

    /// Everything at full strength: Persist with nothing easing back.
    static let fullStrength = FadePolicy(
        isFadeMode: false, delay: 0, outDuration: 0, persistRestoreStart: nil, persistRestoreDuration: 0)

    /// Age at which an annotation is gone in Fade Mode.
    var duration: CFTimeInterval { delay + outDuration }

    /// The alpha an annotation created at `creationTime` draws with at `now`, or nil once
    /// it has faded out.
    func alpha(creationTime: CFTimeInterval?, at now: CFTimeInterval) -> CGFloat? {
        guard let creationTime else { return 1 }
        guard isFadeMode else { return persistRestoreAlpha(creationTime: creationTime, at: now) }
        let age = now - creationTime
        guard age < duration else { return nil }
        return alpha(forAge: age)
    }

    /// Redactions never fade: a hidden secret that reappears on its own defeats the point.
    /// They still go away with Clear All, delete, the eraser and undo like everything else.
    func alpha(for rectangle: Rectangle, at now: CFTimeInterval) -> CGFloat? {
        if rectangle.isRedaction { return 1 }
        return alpha(creationTime: rectangle.creationTime, at: now)
    }

    /// Whether Persist is still easing dimmed annotations back at `now`.
    func isRestoring(at now: CFTimeInterval) -> Bool {
        guard let start = persistRestoreStart else { return false }
        return now - start < persistRestoreDuration
    }

    /// Full opacity through the hold, then an eased fade from 1 to 0 over `outDuration`.
    /// The curve leaves 1 with zero slope, so the fade never starts with a visible step.
    private func alpha(forAge age: CFTimeInterval) -> CGFloat {
        guard age > delay else { return 1 }
        let progress = min(1, (age - delay) / outDuration)
        return CGFloat(1 - Self.smoothstep(progress))
    }

    /// In Persist, eases an annotation from the alpha it had when Fade Mode turned off back
    /// to full strength over `persistRestoreDuration`.
    private func persistRestoreAlpha(creationTime: CFTimeInterval, at now: CFTimeInterval) -> CGFloat {
        guard let start = persistRestoreStart else { return 1 }
        let progress = (now - start) / persistRestoreDuration
        guard progress < 1 else { return 1 }
        let from = alpha(forAge: start - creationTime)
        return from + (1 - from) * CGFloat(Self.smoothstep(max(0, progress)))
    }

    /// 0 at 0 and 1 at 1, with zero slope at both ends.
    private static func smoothstep(_ progress: Double) -> Double {
        progress * progress * (3 - 2 * progress)
    }
}

/// Whether a board covers the screen, and which one. Annotation colors adapt to it.
struct BoardAppearance: Equatable {
    var isVisible: Bool
    var type: BoardView.BoardType

    static let hidden = BoardAppearance(isVisible: false, type: .whiteboard)

    /// `color` as drawn over this board: black and white swap to stay visible, and other
    /// colors shift slightly toward the board's ink. Unchanged when no board is up.
    func adapt(_ color: NSColor) -> NSColor {
        guard isVisible else { return color }

        if type == .blackboard && color.isEqual(NSColor.black) {
            return NSColor.white
        } else if type == .whiteboard && color.isEqual(NSColor.white) {
            return NSColor.black
        }

        if type == .blackboard && color.contrastingColor() == .white {
            return color.blended(withFraction: 0.1, of: NSColor.white) ?? color
        }

        if type == .whiteboard && color.contrastingColor() == .black {
            return color.blended(withFraction: 0.1, of: NSColor.black) ?? color
        }

        return color
    }

    /// Fill used for solid redactions and as the stand-in while a sample is missing. Plain
    /// black everywhere except on a visible blackboard, where a dark gray keeps the
    /// redaction distinguishable from the board itself.
    var redactionPlaceholderColor: NSColor {
        isVisible && type == .blackboard ? NSColor(white: 0.25, alpha: 1) : .black
    }
}

/// The shapes and strokes still under the mouse. `OverlayView` holds them outside the
/// document, and they always draw at full strength on top of their layer.
struct LivePreviews {
    var arrow: Arrow?
    var line: Line?
    var path: DrawingPath?
    /// The path's geometry, extended point by point while the stroke is drawn.
    var pathBezier: NSBezierPath?
    var highlight: DrawingPath?
    var highlightBezier: NSBezierPath?
    var rectangle: Rectangle?
    var circle: Circle?
}

/// Paints an `OverlayDocument` into a graphics context, in the order
/// `OverlayDocument.paintOrder()` defines.
///
/// Everything it needs comes in as values, so it draws the same picture into the overlay
/// view or into an offscreen bitmap. It never draws selection chrome: `OverlayView` paints
/// that over the renderer's output, so a picture made without the view has none.
@MainActor
struct AnnotationRenderer {
    var document: OverlayDocument
    /// Live previews to paint, or nil to leave them out.
    var live: LivePreviews?
    var board: BoardAppearance
    var fade: FadePolicy
    /// The time fade alphas are measured at.
    var now: CFTimeInterval
    /// The area the context covers, in the document's points. Redaction samples clip to it.
    var canvas: NSRect
    /// Only items whose bounds reach this rect paint.
    var dirtyRect: NSRect = .infinite

    /// Slop added to a label that draws without a background, so hit testing, erasing and
    /// marquee selection stay as forgiving as they were before background pills existed.
    /// Labels are also culled against this rect.
    static var plainLabelSlop: NSEdgeInsets { NSEdgeInsets(top: 4, left: 0, bottom: 0, right: 4) }

    /// Paints into `context`, whose user space is the document's points with the origin at
    /// the bottom left.
    func draw(in context: CGContext) {
        if NSGraphicsContext.current?.cgContext === context {
            drawSteps()
            return
        }
        // Text and redaction samples draw through the current AppKit context.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        drawSteps()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSteps() {
        for step in document.paintOrder() {
            switch step {
            case let .content(content, layer, includesLive):
                draw(content, in: layer, live: includesLive ? live : nil)
            case .redaction(let index):
                let rectangle = document.rectangles[index]
                if isDirty(rectangle.redrawBounds) {
                    drawRectangle(rectangle, alpha: 1)
                }
            case .liveRedaction:
                if let rectangle = live?.rectangle, rectangle.isRedaction, isDirty(rectangle.redrawBounds) {
                    drawRectangle(rectangle, alpha: 1)
                }
            case .selection:
                // Chrome belongs to the view, which paints it after this pass.
                break
            }
        }
    }

    /// Paints the committed `content` created within `layer`, then the item of that kind
    /// still being drawn from `live`, which belongs on top.
    private func draw(_ content: OverlayContent, in layer: OverlayDocument.RedactionLayer, live: LivePreviews?) {
        switch content {
        case .arrows:
            for arrow in document.arrows where layer.contains(arrow.creationTime) {
                guard let alpha = fade.alpha(creationTime: arrow.creationTime, at: now) else { continue }
                guard isDirty(arrow.redrawBounds) else { continue }
                drawArrow(
                    from: arrow.startPoint,
                    to: arrow.endPoint,
                    color: arrow.color.withAlphaComponent(alpha),
                    lineWidth: arrow.lineWidth
                )
            }

            if let arrow = live?.arrow, isDirty(arrow.redrawBounds) {
                drawArrow(from: arrow.startPoint, to: arrow.endPoint, color: arrow.color, lineWidth: arrow.lineWidth)
            }

        case .lines:
            for line in document.lines where layer.contains(line.creationTime) {
                guard let alpha = fade.alpha(creationTime: line.creationTime, at: now) else { continue }
                guard isDirty(line.redrawBounds) else { continue }
                drawLine(
                    from: line.startPoint,
                    to: line.endPoint,
                    color: line.color.withAlphaComponent(alpha),
                    lineWidth: line.lineWidth
                )
            }

            if let line = live?.line, isDirty(line.redrawBounds) {
                drawLine(from: line.startPoint, to: line.endPoint, color: line.color, lineWidth: line.lineWidth)
            }

        case .penStrokes:
            for path in document.paths where layer.contains(path.creationTime) {
                guard let alpha = fade.alpha(creationTime: path.creationTime, at: now) else { continue }
                guard isDirty(path.redrawBounds(tool: .pen)) else { continue }
                drawPath(path, tool: .pen, alpha: alpha, bezierPath: path.bezierPath)
            }

            if let path = live?.path, isDirty(path.redrawBounds(tool: .pen)) {
                drawPath(path, tool: .pen, alpha: 1, bezierPath: live?.pathBezier)
            }

        case .highlights:
            for path in document.highlightPaths where layer.contains(path.creationTime) {
                guard let alpha = fade.alpha(creationTime: path.creationTime, at: now) else { continue }
                guard isDirty(path.redrawBounds(tool: .highlighter)) else { continue }
                drawPath(path, tool: .highlighter, alpha: alpha, bezierPath: path.bezierPath)
            }

            if let highlight = live?.highlight, isDirty(highlight.redrawBounds(tool: .highlighter)) {
                drawPath(highlight, tool: .highlighter, alpha: 1, bezierPath: live?.highlightBezier)
            }

        case .outlines:
            for rectangle in document.rectangles
            where !rectangle.isRedaction && layer.contains(rectangle.creationTime) {
                guard let alpha = fade.alpha(for: rectangle, at: now) else { continue }
                guard isDirty(rectangle.redrawBounds) else { continue }
                drawRectangle(rectangle, alpha: alpha)
            }

            if let rectangle = live?.rectangle, !rectangle.isRedaction, isDirty(rectangle.redrawBounds) {
                drawRectangle(rectangle, alpha: 1)
            }

        case .circles:
            for circle in document.circles where layer.contains(circle.creationTime) {
                guard let alpha = fade.alpha(creationTime: circle.creationTime, at: now) else { continue }
                guard isDirty(circle.redrawBounds) else { continue }
                drawCircle(circle, alpha: alpha)
            }

            if let circle = live?.circle, isDirty(circle.redrawBounds) {
                drawCircle(circle, alpha: 1)
            }

        case .labels:
            for (index, annotation) in document.textAnnotations.enumerated()
            where layer.contains(annotation.creationTime) {
                if index == document.editingTextAnnotationIndex { continue }
                guard let alpha = fade.alpha(creationTime: annotation.creationTime, at: now) else { continue }
                let textRect = Self.textRect(for: annotation)
                guard isDirty(textRect) else { continue }
                drawText(annotation, alpha: alpha, bounds: textRect)
            }

        case .counters:
            for counter in document.counterAnnotations where layer.contains(counter.creationTime) {
                guard let alpha = fade.alpha(creationTime: counter.creationTime, at: now) else { continue }
                guard isDirty(counter.badgeRect) else { continue }
                drawCounter(counter, alpha: alpha)
            }
        }
    }

    /// The rect a label occupies on the canvas: its pill, or its text plus `plainLabelSlop`.
    static func textRect(for annotation: TextAnnotation) -> NSRect {
        annotation.bounds(fallbackInsets: plainLabelSlop)
    }

    static func makeBezierPath(points: [TimedPoint]) -> NSBezierPath {
        let bezierPath = NSBezierPath()
        guard let firstPoint = points.first else { return bezierPath }

        bezierPath.move(to: firstPoint.point)
        for timedPoint in points.dropFirst() {
            bezierPath.line(to: timedPoint.point)
        }
        return bezierPath
    }

    private func isDirty(_ bounds: NSRect) -> Bool {
        if bounds.isNull { return false }
        return bounds.intersects(dirtyRect)
    }

    // MARK: - Primitives

    private func drawArrow(from start: NSPoint, to end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        let adaptedColor = board.adapt(color)

        // Calculate arrow head dimensions for equilateral triangle
        // Scale arrowhead size relative to line width, with a minimum and reasonable multiplier
        let sideLength: CGFloat = max(10.0, lineWidth * 4.0)

        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)

        // For an equilateral triangle, the height is (sqrt(3)/2) * side_length
        // and the base width is equal to side_length
        let height = sideLength * sqrt(3.0) / 2.0
        let halfBase = sideLength / 2.0

        // Calculate the base center of the equilateral triangle
        let baseCenter = NSPoint(
            x: end.x - height * cos(angle),
            y: end.y - height * sin(angle)
        )

        // Calculate the two base corners perpendicular to the arrow direction
        let perpAngle = angle + .pi / 2
        let p1 = NSPoint(
            x: baseCenter.x + halfBase * cos(perpAngle),
            y: baseCenter.y + halfBase * sin(perpAngle)
        )
        let p2 = NSPoint(
            x: baseCenter.x - halfBase * cos(perpAngle),
            y: baseCenter.y - halfBase * sin(perpAngle)
        )

        // Draw the line from start to the base center of the triangle
        let linePath = NSBezierPath()
        linePath.move(to: start)
        linePath.line(to: baseCenter)
        adaptedColor.setStroke()
        linePath.lineWidth = lineWidth
        linePath.stroke()

        // Draw filled equilateral triangle
        let trianglePath = NSBezierPath()
        trianglePath.move(to: end)
        trianglePath.line(to: p1)
        trianglePath.line(to: p2)
        trianglePath.close()
        adaptedColor.setFill()
        trianglePath.fill()
    }

    private func drawLine(from start: NSPoint, to end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        let adaptedColor = board.adapt(color)

        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)

        adaptedColor.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    private func drawRectangle(_ rectangle: Rectangle, alpha: CGFloat) {
        let rect = rectangle.bounds
        guard rectangle.style == .outline else {
            drawRedaction(rectangle, in: rect)
            return
        }

        let adaptedColor = board.adapt(rectangle.color)
        let path = NSBezierPath(rect: rect)
        adaptedColor.withAlphaComponent(alpha).setStroke()
        path.lineWidth = rectangle.lineWidth
        path.stroke()
    }

    /// Always lays down the opaque placeholder first so nothing shows through, then paints
    /// the filtered pixels over it when they are available and safe to show. Solid stays
    /// solid: wherever a solid redaction overlaps, the placeholder goes back on top, even
    /// over an older one, since the sample shows filtered real screen content. A visible
    /// board hides what is behind it, so its redactions stay solid.
    private func drawRedaction(_ rectangle: Rectangle, in rect: NSRect) {
        board.redactionPlaceholderColor.setFill()
        rect.fill()

        guard rectangle.needsSample, let sample = rectangle.sample,
            sample.key.style == rectangle.style, !board.isVisible,
            let context = NSGraphicsContext.current?.cgContext
        else { return }
        let visible = rect.intersection(canvas)
        guard !visible.isEmpty else { return }
        context.saveGState()
        // The sample paints where its pixels came from. Mid-drag it can lag behind the
        // rectangle, so clipping leaves any part it does not cover on the placeholder.
        context.clip(to: visible)
        // Pixelate is stored one pixel per block and blur at reduced resolution, so both
        // scale up here: hard edges keep the blocks, smooth interpolation keeps the blur soft.
        context.interpolationQuality = rectangle.style == .pixelate ? .none : .high
        context.draw(sample.image, in: sample.bounds)
        context.restoreGState()

        board.redactionPlaceholderColor.setFill()
        func fillOverlap(with solid: Rectangle) {
            let overlap = rect.intersection(solid.bounds)
            if !overlap.isEmpty { overlap.fill() }
        }
        for solid in document.rectangles where solid.style == .solid {
            fillOverlap(with: solid)
        }
        if let solid = live?.rectangle, solid.style == .solid {
            fillOverlap(with: solid)
        }
    }

    private func drawCircle(_ circle: Circle, alpha: CGFloat) {
        let adaptedColor = board.adapt(circle.color)

        let rect = NSRect(
            x: min(circle.startPoint.x, circle.endPoint.x),
            y: min(circle.startPoint.y, circle.endPoint.y),
            width: abs(circle.endPoint.x - circle.startPoint.x),
            height: abs(circle.endPoint.y - circle.startPoint.y)
        )

        let path = NSBezierPath(ovalIn: rect)
        adaptedColor.withAlphaComponent(alpha).setStroke()
        path.lineWidth = circle.lineWidth
        path.stroke()
    }

    private func drawPath(
        _ path: DrawingPath,
        tool: ToolType,
        alpha: CGFloat,
        bezierPath: NSBezierPath? = nil
    ) {
        guard !path.points.isEmpty else { return }

        let adaptedColor = board.adapt(path.color)
        let renderedPath = bezierPath ?? Self.makeBezierPath(points: path.points)

        adaptedColor.withAlphaComponent(tool.laydownAlpha * alpha).setStroke()
        renderedPath.lineWidth = path.lineWidth * tool.strokeWidthMultiplier
        renderedPath.lineJoinStyle = .round
        renderedPath.lineCapStyle = .round
        renderedPath.stroke()
    }

    /// Draws a label. `bounds` is the rect from `textRect(for:)`, which for a label with a
    /// background is exactly the pill.
    private func drawText(_ annotation: TextAnnotation, alpha: CGFloat, bounds: NSRect) {
        let adaptedColor = board.adapt(annotation.color)

        if annotation.hasBackground {
            let pill = NSBezierPath(
                roundedRect: bounds,
                xRadius: TextAnnotation.pillCornerRadius,
                yRadius: TextAnnotation.pillCornerRadius
            )
            adaptedColor.contrastingColor()
                .withAlphaComponent(TextAnnotation.pillFillAlpha * alpha)
                .setFill()
            pill.fill()
        }

        // The same layout `textSize()` measures, so wrapped lines break where the box
        // expects them and where the editor showed them.
        let layout = annotation.textLayout(color: adaptedColor.withAlphaComponent(alpha))
        layout.draw(
            topLeft: NSPoint(x: annotation.position.x, y: annotation.position.y + layout.size.height))
    }

    private func drawCounter(_ counter: CounterAnnotation, alpha: CGFloat) {
        let adaptedColor = board.adapt(counter.color)

        let circlePath = NSBezierPath(ovalIn: counter.badgeRect)

        let numberColor: NSColor
        switch counter.style {
        case .bordered:
            let backgroundColor = adaptedColor.contrastingColor()
            backgroundColor.withAlphaComponent(0.7 * alpha).setFill()
            circlePath.fill()

            adaptedColor.withAlphaComponent(alpha).setStroke()
            circlePath.lineWidth = counter.strokeWidth
            circlePath.stroke()
            numberColor = adaptedColor
        case .filled:
            adaptedColor.withAlphaComponent(alpha).setFill()
            circlePath.fill()
            numberColor = CounterAnnotation.filledNumberColor(on: adaptedColor)
        }

        // Draw the number
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: numberColor.withAlphaComponent(alpha),
            .font: NSFont.systemFont(ofSize: counter.fontSize, weight: .heavy),
            .paragraphStyle: paragraphStyle,
        ]

        let numberString = "\(counter.number)"
        let textSize = numberString.size(withAttributes: attributes)

        // Center the text in the circle
        let textRect = NSRect(
            x: counter.position.x - textSize.width / 2,
            y: counter.position.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )

        numberString.draw(in: textRect, withAttributes: attributes)
    }
}

// MARK: - Paint bounds

// Where each annotation can paint, padded for stroke width and antialiasing. The renderer
// culls against these and `OverlayView` invalidates them, so both use the same math.

extension AnnotationRenderer {
    /// The rect spanned by `start` and `end`, grown by `padding` on every side.
    nonisolated static func paddedBounds(_ start: NSPoint, _ end: NSPoint, padding: CGFloat) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).insetBy(dx: -padding, dy: -padding)
    }
}

extension Rectangle {
    var redrawBounds: NSRect { AnnotationRenderer.paddedBounds(startPoint, endPoint, padding: lineWidth / 2 + 6) }
}

extension Arrow {
    /// Padded wide enough for the arrowhead.
    var redrawBounds: NSRect { AnnotationRenderer.paddedBounds(startPoint, endPoint, padding: max(lineWidth * 4, 30)) }
}

extension Line {
    var redrawBounds: NSRect { AnnotationRenderer.paddedBounds(startPoint, endPoint, padding: lineWidth / 2 + 6) }
}

extension Circle {
    var redrawBounds: NSRect { AnnotationRenderer.paddedBounds(startPoint, endPoint, padding: lineWidth / 2 + 6) }
}

extension DrawingPath {
    /// Bounds of the stroke as `tool` draws it, or `.null` for a path with no points.
    func redrawBounds(tool: ToolType) -> NSRect {
        let padding = lineWidth * tool.strokeWidthMultiplier / 2 + 6
        let bounds = cachedBounds.isNull ? DrawingPath.bounds(of: points) : cachedBounds
        guard !bounds.isNull else { return .null }
        return bounds.insetBy(dx: -padding, dy: -padding)
    }
}
