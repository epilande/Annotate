import Cocoa

@MainActor
class OverlayView: NSView, NSTextFieldDelegate {
    var adaptColorsToBoardType: Bool = true

    var arrows: [Arrow] = []
    var currentArrow: Arrow?

    var lines: [Line] = []
    var currentLine: Line?

    var paths: [DrawingPath] = []
    var currentPath: DrawingPath?

    var highlightPaths: [DrawingPath] = []
    var currentHighlight: DrawingPath?

    var rectangles: [Rectangle] = []
    var currentRectangle: Rectangle?

    var circles: [Circle] = []
    var currentCircle: Circle?

    var textAnnotations: [TextAnnotation] = []
    var currentTextAnnotation: TextAnnotation?
    var activeTextField: NSTextField?
    var originalTextPosition: NSPoint?
    var draggedTextAnnotationIndex: Int?
    var dragOffset: NSPoint?
    var editingTextAnnotationIndex: Int?

    var counterAnnotations: [CounterAnnotation] = []
    var nextCounterNumber: Int = 1

    let eraserRadius: CGFloat = 12.0

    var selectedObjects: Set<SelectedObject> = []
    var selectionDragOffset: NSPoint?
    var selectionOriginalData: [SelectedObject: Any] = [:]

    var isDrawingSelectionRect: Bool = false
    var selectionRectStart: NSPoint?
    var selectionRectEnd: NSPoint?

    var clipboard: [ClipboardItem] = []
    var lastMousePosition: NSPoint = .zero

    var currentColor: NSColor = .systemRed
    var currentTool: ToolType = .pen
    var currentLineWidth: CGFloat = 3.0

    var fadeMode: Bool = true
    let fadeDuration: CFTimeInterval = 1.25
    var isReadOnlyMode: Bool = false

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    override var undoManager: UndoManager? {
        return window?.undoManager
    }

    func undo() {
        undoManager?.undo()
    }

    func redo() {
        undoManager?.redo()
    }

    func registerUndo(action: DrawingAction) {
        let manager = undoManager
        switch action {
        case .addPath(let path):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if !target.paths.isEmpty {
                        target.paths.removeLast()
                        target.registerUndo(action: .removePath(path))
                        target.needsDisplay = true
                    }
                }
            }
        case .addArrow(let arrow):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if !target.arrows.isEmpty {
                        target.arrows.removeLast()
                        target.registerUndo(action: .removeArrow(arrow))
                        target.needsDisplay = true
                    }
                }
            }
        case .addLine(let line):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if !target.lines.isEmpty {
                        target.lines.removeLast()
                        target.registerUndo(action: .removeLine(line))
                        target.needsDisplay = true
                    }
                }
            }
        case .addHighlight(let highlight):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if !target.highlightPaths.isEmpty {
                        target.highlightPaths.removeLast()
                        target.registerUndo(action: .removeHighlight(highlight))
                        target.needsDisplay = true
                    }
                }
            }
        case .removePath(let path):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.paths.append(path)
                    target.registerUndo(action: .addPath(path))
                    target.needsDisplay = true
                }
            }
        case .removeArrow(let arrow):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.arrows.append(arrow)
                    target.registerUndo(action: .addArrow(arrow))
                    target.needsDisplay = true
                }
            }
        case .removeLine(let line):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.lines.append(line)
                    target.registerUndo(action: .addLine(line))
                    target.needsDisplay = true
                }
            }
        case .removeHighlight(let highlight):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.highlightPaths.append(highlight)
                    target.registerUndo(action: .addHighlight(highlight))
                    target.needsDisplay = true
                }
            }
        case .addRectangle(let rectangle):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if !target.rectangles.isEmpty {
                        target.rectangles.removeLast()
                        target.registerUndo(action: .removeRectangle(rectangle))
                        target.needsDisplay = true
                    }
                }
            }
        case .removeRectangle(let rectangle):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.rectangles.append(rectangle)
                    target.registerUndo(action: .addRectangle(rectangle))
                    target.needsDisplay = true
                }
            }
        case .addCircle(let circle):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if !target.circles.isEmpty {
                        target.circles.removeLast()
                        target.registerUndo(action: .removeCircle(circle))
                        target.needsDisplay = true
                    }
                }
            }
        case .removeCircle(let circle):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.circles.append(circle)
                    target.registerUndo(action: .addCircle(circle))
                    target.needsDisplay = true
                }
            }
        case .addText(let annotation):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if !target.textAnnotations.isEmpty {
                        target.textAnnotations.removeLast()
                        target.registerUndo(action: .removeText(annotation))
                        target.needsDisplay = true
                    }
                }
            }
        case .removeText(let annotation):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.textAnnotations.append(annotation)
                    target.registerUndo(action: .addText(annotation))
                    target.needsDisplay = true
                }
            }
        case .moveText(let index, let oldPosition, let newPosition):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if index < target.textAnnotations.count {
                        target.textAnnotations[index].position = oldPosition
                        target.registerUndo(action: .moveText(index, newPosition, oldPosition))
                        target.needsDisplay = true
                    }
                }
            }
        case .moveArrow(let index, let fromStart, let fromEnd, let toStart, let toEnd):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if index < target.arrows.count {
                        target.arrows[index].startPoint = fromStart
                        target.arrows[index].endPoint = fromEnd
                        target.registerUndo(action: .moveArrow(index, toStart, toEnd, fromStart, fromEnd))
                        target.needsDisplay = true
                    }
                }
            }
        case .moveLine(let index, let fromStart, let fromEnd, let toStart, let toEnd):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if index < target.lines.count {
                        target.lines[index].startPoint = fromStart
                        target.lines[index].endPoint = fromEnd
                        target.registerUndo(action: .moveLine(index, toStart, toEnd, fromStart, fromEnd))
                        target.needsDisplay = true
                    }
                }
            }
        case .moveRectangle(let index, let fromStart, let fromEnd, let toStart, let toEnd):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if index < target.rectangles.count {
                        target.rectangles[index].startPoint = fromStart
                        target.rectangles[index].endPoint = fromEnd
                        target.registerUndo(action: .moveRectangle(index, toStart, toEnd, fromStart, fromEnd))
                        target.needsDisplay = true
                    }
                }
            }
        case .moveCircle(let index, let fromStart, let fromEnd, let toStart, let toEnd):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if index < target.circles.count {
                        target.circles[index].startPoint = fromStart
                        target.circles[index].endPoint = fromEnd
                        target.registerUndo(action: .moveCircle(index, toStart, toEnd, fromStart, fromEnd))
                        target.needsDisplay = true
                    }
                }
            }
        case .movePath(let index, let delta):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if index < target.paths.count {
                        // Undo: move back by negative delta
                        for i in 0..<target.paths[index].points.count {
                            target.paths[index].points[i].point.x -= delta.x
                            target.paths[index].points[i].point.y -= delta.y
                        }
                        target.registerUndo(action: .movePath(index, NSPoint(x: -delta.x, y: -delta.y)))
                        target.needsDisplay = true
                    }
                }
            }
        case .moveHighlight(let index, let delta):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if index < target.highlightPaths.count {
                        // Undo: move back by negative delta
                        for i in 0..<target.highlightPaths[index].points.count {
                            target.highlightPaths[index].points[i].point.x -= delta.x
                            target.highlightPaths[index].points[i].point.y -= delta.y
                        }
                        target.registerUndo(action: .moveHighlight(index, NSPoint(x: -delta.x, y: -delta.y)))
                        target.needsDisplay = true
                    }
                }
            }
        case .moveCounter(let index, let from, let to):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if index < target.counterAnnotations.count {
                        target.counterAnnotations[index].position = from
                        target.registerUndo(action: .moveCounter(index, to, from))
                        target.needsDisplay = true
                    }
                }
            }
        case .addCounter(let counter):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    if !target.counterAnnotations.isEmpty {
                        target.counterAnnotations.removeLast()
                        target.nextCounterNumber = max(1, target.nextCounterNumber - 1)
                        target.registerUndo(action: .removeCounter(counter))
                        target.needsDisplay = true
                    }
                }
            }
        case .removeCounter(let counter):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.counterAnnotations.append(counter)
                    target.nextCounterNumber = max(target.nextCounterNumber, counter.number + 1)
                    target.registerUndo(action: .addCounter(counter))
                    target.needsDisplay = true
                }
            }
        case .clearAll(
            let paths, let arrows, let lines, let highlights, let rectangles, let circles,
            let textAnnotations,
            let counterAnnotations):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.paths = paths
                    target.arrows = arrows
                    target.lines = lines
                    target.highlightPaths = highlights
                    target.rectangles = rectangles
                    target.circles = circles
                    target.textAnnotations = textAnnotations
                    target.counterAnnotations = counterAnnotations
                    target.nextCounterNumber =
                        counterAnnotations.map { $0.number }.max().map { $0 + 1 } ?? 1
                    target.registerUndo(action: .clearAll([], [], [], [], [], [], [], []))
                    target.needsDisplay = true
                }
            }
        case .pasteObjects(_):
            // Paste undo is handled by individual add actions for each pasted object
            break
        case .cutObjects(_):
            // Cut undo is handled by individual remove actions for each cut object
            break
        case .eraseAnnotations(
            let paths, let arrows, let lines, let highlights, let rectangles, let circles,
            let textAnnotations, let counterAnnotations):
            // Reciprocal undo pattern: eraseAnnotations ↔ restoreAnnotations
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.paths.append(contentsOf: paths)
                    target.arrows.append(contentsOf: arrows)
                    target.lines.append(contentsOf: lines)
                    target.highlightPaths.append(contentsOf: highlights)
                    target.rectangles.append(contentsOf: rectangles)
                    target.circles.append(contentsOf: circles)
                    target.textAnnotations.append(contentsOf: textAnnotations)
                    target.counterAnnotations.append(contentsOf: counterAnnotations)
                    target.nextCounterNumber =
                        target.counterAnnotations.map { $0.number }.max().map { $0 + 1 } ?? 1
                    target.registerUndo(action: .restoreAnnotations(
                        paths, arrows, lines, highlights, rectangles, circles, textAnnotations, counterAnnotations
                    ))
                    target.needsDisplay = true
                }
            }
        case .restoreAnnotations(
            let paths, let arrows, let lines, let highlights, let rectangles, let circles,
            let textAnnotations, let counterAnnotations):
            manager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    target.paths.removeAll { item in paths.contains(item) }
                    target.arrows.removeAll { item in arrows.contains(item) }
                    target.lines.removeAll { item in lines.contains(item) }
                    target.highlightPaths.removeAll { item in highlights.contains(item) }
                    target.rectangles.removeAll { item in rectangles.contains(item) }
                    target.circles.removeAll { item in circles.contains(item) }
                    target.textAnnotations.removeAll { item in textAnnotations.contains(item) }
                    target.counterAnnotations.removeAll { item in counterAnnotations.contains(item) }
                    target.nextCounterNumber =
                        target.counterAnnotations.map { $0.number }.max().map { $0 + 1 } ?? 1
                    target.registerUndo(action: .eraseAnnotations(
                        paths, arrows, lines, highlights, rectangles, circles, textAnnotations, counterAnnotations
                    ))
                    target.needsDisplay = true
                }
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let now = CACurrentMediaTime()

        // Draw arrows
        var aliveArrows: [Arrow] = []
        for arrow in arrows {
            if fadeMode, let creationTime = arrow.creationTime {
                let age = now - creationTime
                if age < fadeDuration {
                    let alpha = alphaForAge(age)
                    drawArrow(
                        from: arrow.startPoint,
                        to: arrow.endPoint,
                        color: arrow.color.withAlphaComponent(alpha),
                        lineWidth: arrow.lineWidth
                    )
                    aliveArrows.append(arrow)
                }
            } else {
                drawArrow(from: arrow.startPoint, to: arrow.endPoint, color: arrow.color, lineWidth: arrow.lineWidth)
                aliveArrows.append(arrow)
            }
        }
        arrows = aliveArrows

        // Draw current arrow being drawn
        if let arrow = currentArrow {
            drawArrow(from: arrow.startPoint, to: arrow.endPoint, color: arrow.color, lineWidth: arrow.lineWidth)
        }

        // Draw lines
        var aliveLines: [Line] = []
        for line in lines {
            if fadeMode, let creationTime = line.creationTime {
                let age = now - creationTime
                if age < fadeDuration {
                    let alpha = alphaForAge(age)
                    drawLine(
                        from: line.startPoint,
                        to: line.endPoint,
                        color: line.color.withAlphaComponent(alpha),
                        lineWidth: line.lineWidth
                    )
                    aliveLines.append(line)
                }
            } else {
                drawLine(from: line.startPoint, to: line.endPoint, color: line.color, lineWidth: line.lineWidth)
                aliveLines.append(line)
            }
        }
        lines = aliveLines

        // Draw current line being drawn
        if let line = currentLine {
            drawLine(from: line.startPoint, to: line.endPoint, color: line.color, lineWidth: line.lineWidth)
        }

        // Draw existing paths
        var alivePaths: [DrawingPath] = []
        for path in paths {
            if fadeMode {
                let pathRemaining = drawPathWithFading(path, now: now, isHighlighter: false)
                if !pathRemaining.isEmpty {
                    var newPath = path
                    newPath.points = pathRemaining
                    alivePaths.append(newPath)
                }
            } else {
                drawPath(path, tool: .pen)
                alivePaths.append(path)
            }
        }
        paths = alivePaths

        if let path = currentPath {
            drawPath(path, tool: .pen)
        }

        // Draw highlighter paths
        var aliveHighlights: [DrawingPath] = []
        for path in highlightPaths {
            if fadeMode {
                let pathRemaining = drawPathWithFading(path, now: now, isHighlighter: true)
                if !pathRemaining.isEmpty {
                    var newHighlight = path
                    newHighlight.points = pathRemaining
                    aliveHighlights.append(newHighlight)
                }
            } else {
                drawPath(path, tool: .highlighter)
                aliveHighlights.append(path)
            }
        }
        highlightPaths = aliveHighlights

        if let highlight = currentHighlight {
            drawPath(highlight, tool: .highlighter)
        }

        // Draw rectangles
        var aliveRects: [Rectangle] = []
        for rect in rectangles {
            if fadeMode, let creationTime = rect.creationTime {
                let age = now - creationTime
                if age < fadeDuration {
                    let alpha = alphaForAge(age)
                    drawRectangle(rect, alpha: alpha)
                    aliveRects.append(rect)
                }
            } else {
                drawRectangle(rect, alpha: 1.0)
                aliveRects.append(rect)
            }
        }
        rectangles = aliveRects

        if let rectangle = currentRectangle {
            drawRectangle(rectangle, alpha: 1.0)
        }

        // Draw circles
        var aliveCircles: [Circle] = []
        for circle in circles {
            if fadeMode, let creationTime = circle.creationTime {
                let age = now - creationTime
                if age < fadeDuration {
                    let alpha = alphaForAge(age)
                    drawCircle(circle, alpha: alpha)
                    aliveCircles.append(circle)
                }
            } else {
                drawCircle(circle, alpha: 1.0)
                aliveCircles.append(circle)
            }
        }
        circles = aliveCircles

        if let circle = currentCircle {
            drawCircle(circle, alpha: 1.0)
        }

        // Draw texts
        for annotation in textAnnotations {
            drawText(annotation)
        }
        if let annotation = currentTextAnnotation {
            drawText(annotation)
        }

        var aliveCounters: [CounterAnnotation] = []
        for counter in counterAnnotations {
            if fadeMode, let creationTime = counter.creationTime {
                let age = now - creationTime
                if age < fadeDuration {
                    let alpha = alphaForAge(age)
                    drawCounter(counter, alpha: alpha)
                    aliveCounters.append(counter)
                }
            } else {
                drawCounter(counter, alpha: 1.0)
                aliveCounters.append(counter)
            }
        }
        counterAnnotations = aliveCounters
        
        // Draw selection bounding box for all selected objects
        if !selectedObjects.isEmpty {
            let boundingBox = calculateSelectionBoundingBox()
            drawSelectionBoundingBox(boundingBox)
        }
        
        // Draw selection rectangle if being drawn
        if isDrawingSelectionRect, let start = selectionRectStart, let end = selectionRectEnd {
            let rect = NSRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )

            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2.0
            path.setLineDash([5.0, 3.0], count: 2, phase: 0)
            NSColor.systemBlue.withAlphaComponent(0.3).setFill()
            NSColor.systemBlue.setStroke()
            path.fill()
            path.stroke()
        }
    }
    
    // MARK: - Selection Bounding Box
    
    func calculateSelectionBoundingBox() -> NSRect {
        guard !selectedObjects.isEmpty else { return .zero }
        
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        
        for obj in selectedObjects {
            let objBounds = getObjectBounds(obj)
            minX = min(minX, objBounds.minX)
            minY = min(minY, objBounds.minY)
            maxX = max(maxX, objBounds.maxX)
            maxY = max(maxY, objBounds.maxY)
        }
        
        // Add padding
        let padding: CGFloat = 5.0
        return NSRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + (padding * 2),
            height: (maxY - minY) + (padding * 2)
        )
    }
    
    func getObjectBounds(_ object: SelectedObject) -> NSRect {
        switch object {
        case .arrow(let index):
            guard index < arrows.count else { return .zero }
            let arrow = arrows[index]
            return NSRect(
                x: min(arrow.startPoint.x, arrow.endPoint.x),
                y: min(arrow.startPoint.y, arrow.endPoint.y),
                width: abs(arrow.endPoint.x - arrow.startPoint.x),
                height: abs(arrow.endPoint.y - arrow.startPoint.y)
            )
            
        case .line(let index):
            guard index < lines.count else { return .zero }
            let line = lines[index]
            return NSRect(
                x: min(line.startPoint.x, line.endPoint.x),
                y: min(line.startPoint.y, line.endPoint.y),
                width: abs(line.endPoint.x - line.startPoint.x),
                height: abs(line.endPoint.y - line.startPoint.y)
            )
            
        case .rectangle(let index):
            guard index < rectangles.count else { return .zero }
            let rect = rectangles[index]
            return NSRect(
                x: min(rect.startPoint.x, rect.endPoint.x),
                y: min(rect.startPoint.y, rect.endPoint.y),
                width: abs(rect.endPoint.x - rect.startPoint.x),
                height: abs(rect.endPoint.y - rect.startPoint.y)
            )
            
        case .circle(let index):
            guard index < circles.count else { return .zero }
            let circle = circles[index]
            return NSRect(
                x: min(circle.startPoint.x, circle.endPoint.x),
                y: min(circle.startPoint.y, circle.endPoint.y),
                width: abs(circle.endPoint.x - circle.startPoint.x),
                height: abs(circle.endPoint.y - circle.startPoint.y)
            )
            
        case .path(let index):
            guard index < paths.count else { return .zero }
            let path = paths[index]
            guard !path.points.isEmpty else { return .zero }
            
            var minX = path.points[0].point.x
            var minY = path.points[0].point.y
            var maxX = path.points[0].point.x
            var maxY = path.points[0].point.y
            
            for point in path.points {
                minX = min(minX, point.point.x)
                minY = min(minY, point.point.y)
                maxX = max(maxX, point.point.x)
                maxY = max(maxY, point.point.y)
            }
            
            return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            
        case .highlight(let index):
            guard index < highlightPaths.count else { return .zero }
            let path = highlightPaths[index]
            guard !path.points.isEmpty else { return .zero }
            
            var minX = path.points[0].point.x
            var minY = path.points[0].point.y
            var maxX = path.points[0].point.x
            var maxY = path.points[0].point.y
            
            for point in path.points {
                minX = min(minX, point.point.x)
                minY = min(minY, point.point.y)
                maxX = max(maxX, point.point.x)
                maxY = max(maxY, point.point.y)
            }
            
            return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            
        case .text(let index):
            guard index < textAnnotations.count else { return .zero }
            return getTextRect(for: textAnnotations[index])
            
        case .counter(let index):
            guard index < counterAnnotations.count else { return .zero }
            let counter = counterAnnotations[index]
            let radius: CGFloat = 15.0
            return NSRect(
                x: counter.position.x - radius,
                y: counter.position.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            
        case .none:
            return .zero
        }
    }
    
    private func drawSelectionBoundingBox(_ rect: NSRect) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2.0
        path.setLineDash([5.0, 3.0], count: 2, phase: 0)
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        path.stroke()
    }
    
    /// Check if a point is inside the bounding box of any selected object
    func isPointInSelectionBoundingBox(_ point: NSPoint) -> Bool {
        guard !selectedObjects.isEmpty else { return false }
        let boundingBox = calculateSelectionBoundingBox()
        return boundingBox.contains(point)
    }

    private func alphaForAge(_ age: CFTimeInterval) -> CGFloat {
        let fadeDelay = fadeDuration / 2
        if age <= fadeDelay { return 1.0 }
        let fadeOut = fadeDelay - (age - fadeDelay)
        return CGFloat(max(0, fadeOut))
    }
    
    
    private func drawPathWithFading(_ path: DrawingPath, now: CFTimeInterval, isHighlighter: Bool)
        -> [TimedPoint]
    {
        guard !path.points.isEmpty else { return [] }

        let validPoints = path.points.filter { (now - $0.timestamp) < (fadeDuration / 4) }

        guard validPoints.count > 1 else {
            return validPoints
        }

        let line = NSBezierPath()
        line.move(to: validPoints[0].point)

        for i in 1..<validPoints.count {
            line.line(to: validPoints[i].point)
        }

        if validPoints.count > 1 {
            let strokeColor =
                isHighlighter
                ? path.color.withAlphaComponent(0.5)
                : path.color.withAlphaComponent(1)

            strokeColor.setStroke()
            line.lineWidth = isHighlighter ? path.lineWidth * 4.67 : path.lineWidth
            line.lineJoinStyle = .round
            line.lineCapStyle = .round
            line.stroke()
        }

        return validPoints
    }

    private func drawArrow(from start: NSPoint, to end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        let adaptedColor = adaptColorForBoard(color, boardType: currentBoardType)

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
        let adaptedColor = adaptColorForBoard(color, boardType: currentBoardType)

        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)

        adaptedColor.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    private func drawRectangle(_ rectangle: Rectangle, alpha: CGFloat) {
        let adaptedColor = adaptColorForBoard(rectangle.color, boardType: currentBoardType)

        let rect = NSRect(
            x: min(rectangle.startPoint.x, rectangle.endPoint.x),
            y: min(rectangle.startPoint.y, rectangle.endPoint.y),
            width: abs(rectangle.endPoint.x - rectangle.startPoint.x),
            height: abs(rectangle.endPoint.y - rectangle.startPoint.y)
        )

        let path = NSBezierPath(rect: rect)
        adaptedColor.withAlphaComponent(alpha).setStroke()
        path.lineWidth = rectangle.lineWidth
        path.stroke()
    }

    private func drawCircle(_ circle: Circle, alpha: CGFloat) {
        let adaptedColor = adaptColorForBoard(circle.color, boardType: currentBoardType)

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

    func clearArrows() {
        arrows.removeAll()
        currentArrow = nil
        needsDisplay = true
    }

    private func drawPath(_ path: DrawingPath, tool: ToolType) {
        guard !path.points.isEmpty else { return }

        let adaptedColor = adaptColorForBoard(path.color, boardType: currentBoardType)

        let bezierPath = NSBezierPath()
        bezierPath.move(to: path.points[0].point)

        for timedPoint in path.points.dropFirst() {
            bezierPath.line(to: timedPoint.point)
        }

        if tool == .highlighter {
            adaptedColor.withAlphaComponent(0.5).setStroke()
            bezierPath.lineWidth = path.lineWidth * 4.67  // Maintain the ratio: 14/3 ≈ 4.67
        } else {
            adaptedColor.setStroke()
            bezierPath.lineWidth = path.lineWidth
        }

        bezierPath.lineJoinStyle = .round
        bezierPath.lineCapStyle = .round
        bezierPath.stroke()
    }

    private func drawText(_ annotation: TextAnnotation) {
        let adaptedColor = adaptColorForBoard(annotation.color, boardType: currentBoardType)

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: adaptedColor,
            .font: NSFont.systemFont(ofSize: annotation.fontSize),
        ]
        let attributedString = NSAttributedString(string: annotation.text, attributes: attributes)
        attributedString.draw(at: annotation.position)
    }

    private func drawCounter(_ counter: CounterAnnotation, alpha: CGFloat) {
        let adaptedColor = adaptColorForBoard(counter.color, boardType: currentBoardType)

        let radius: CGFloat = 15.0
        let diameter = radius * 2

        let circleBounds = NSRect(
            x: counter.position.x - radius,
            y: counter.position.y - radius,
            width: diameter,
            height: diameter
        )
        let circlePath = NSBezierPath(ovalIn: circleBounds)

        let backgroundColor = adaptedColor.contrastingColor()
        backgroundColor.withAlphaComponent(0.7 * alpha).setFill()
        circlePath.fill()

        adaptedColor.withAlphaComponent(alpha).setStroke()
        circlePath.lineWidth = 2.5
        circlePath.stroke()

        // Draw the number
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let fontSize: CGFloat = 14.0
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: adaptedColor.withAlphaComponent(alpha),
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
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

    func clearAll() {
        // Only register undo if there's something to clear
        if !paths.isEmpty || !arrows.isEmpty || !lines.isEmpty || !highlightPaths.isEmpty
            || !rectangles.isEmpty
            || !circles.isEmpty || !textAnnotations.isEmpty || !counterAnnotations.isEmpty
        {
            let oldPaths = paths
            let oldArrows = arrows
            let oldLines = lines
            let oldHighlights = highlightPaths
            let oldRectangles = rectangles
            let oldCircles = circles
            let oldTextAnnotations = textAnnotations
            let oldCounterAnnotations = counterAnnotations
            registerUndo(
                action: .clearAll(
                    oldPaths, oldArrows, oldLines, oldHighlights, oldRectangles, oldCircles,
                    oldTextAnnotations, oldCounterAnnotations))

            paths.removeAll()
            arrows.removeAll()
            lines.removeAll()
            highlightPaths.removeAll()
            rectangles.removeAll()
            circles.removeAll()
            textAnnotations.removeAll()
            counterAnnotations.removeAll()
            nextCounterNumber = 1
            currentArrow = nil
            currentLine = nil
            currentPath = nil
            currentHighlight = nil
            currentRectangle = nil
            currentCircle = nil
            currentTextAnnotation = nil

            selectedObjects.removeAll()
            selectionRectStart = nil
            selectionRectEnd = nil
            isDrawingSelectionRect = false
            selectionDragOffset = nil
            selectionOriginalData = [:]

            needsDisplay = true
        }
    }

    func deleteLastItem() {
        switch currentTool {
        case .pen:
            guard !paths.isEmpty else { return }
            let lastPath = paths.last!
            registerUndo(action: .removePath(lastPath))
            paths.removeLast()
        case .arrow:
            guard !arrows.isEmpty else { return }
            let lastArrow = arrows.last!
            registerUndo(action: .removeArrow(lastArrow))
            arrows.removeLast()
        case .line:
            guard !lines.isEmpty else { return }
            let lastLine = lines.last!
            registerUndo(action: .removeLine(lastLine))
            lines.removeLast()
        case .highlighter:
            guard !highlightPaths.isEmpty else { return }
            let lastHighlight = highlightPaths.last!
            registerUndo(action: .removeHighlight(lastHighlight))
            highlightPaths.removeLast()
        case .rectangle:
            guard !rectangles.isEmpty else { return }
            let lastRectangle = rectangles.last!
            registerUndo(action: .removeRectangle(lastRectangle))
            rectangles.removeLast()
        case .circle:
            guard !circles.isEmpty else { return }
            let lastCircle = circles.last!
            registerUndo(action: .removeCircle(lastCircle))
            circles.removeLast()
        case .text:
            guard !textAnnotations.isEmpty else { return }
            let lastText = textAnnotations.last!
            registerUndo(action: .removeText(lastText))
            textAnnotations.removeLast()
        case .counter:
            guard !counterAnnotations.isEmpty else { return }
            let lastCounter = counterAnnotations.last!
            registerUndo(action: .removeCounter(lastCounter))
            counterAnnotations.removeLast()
            nextCounterNumber = max(1, nextCounterNumber - 1)
        case .select:
            // In select mode, delete the selected objects if any
            if !selectedObjects.isEmpty {
                deleteSelectedObjects()
            }
        case .eraser:
            // Eraser doesn't create items, so nothing to delete
            break
        }
        needsDisplay = true
    }
    
    func deleteSelectedObjects() {
        guard !selectedObjects.isEmpty else { return }

        // Sort objects by type and index (descending) to delete from end first
        // This prevents index shifting issues
        let sortedObjects = selectedObjects.sorted { obj1, obj2 in
            let (type1, idx1) = obj1.sortValue
            let (type2, idx2) = obj2.sortValue
            if type1 != type2 { return type1 < type2 }
            return idx1 > idx2 // Descending index order
        }

        for object in sortedObjects {
            deleteObject(object)
        }

        selectedObjects.removeAll()
        needsDisplay = true
    }
    
    private func deleteObject(_ object: SelectedObject) {
        switch object {
        case .arrow(let index):
            guard index < arrows.count else { return }
            let arrow = arrows[index]
            registerUndo(action: .removeArrow(arrow))
            arrows.remove(at: index)
            
        case .line(let index):
            guard index < lines.count else { return }
            let line = lines[index]
            registerUndo(action: .removeLine(line))
            lines.remove(at: index)
            
        case .rectangle(let index):
            guard index < rectangles.count else { return }
            let rect = rectangles[index]
            registerUndo(action: .removeRectangle(rect))
            rectangles.remove(at: index)
            
        case .circle(let index):
            guard index < circles.count else { return }
            let circle = circles[index]
            registerUndo(action: .removeCircle(circle))
            circles.remove(at: index)
            
        case .path(let index):
            guard index < paths.count else { return }
            let path = paths[index]
            registerUndo(action: .removePath(path))
            paths.remove(at: index)
            
        case .highlight(let index):
            guard index < highlightPaths.count else { return }
            let highlight = highlightPaths[index]
            registerUndo(action: .removeHighlight(highlight))
            highlightPaths.remove(at: index)
            
        case .text(let index):
            guard index < textAnnotations.count else { return }
            let text = textAnnotations[index]
            registerUndo(action: .removeText(text))
            textAnnotations.remove(at: index)
            
        case .counter(let index):
            guard index < counterAnnotations.count else { return }
            let counter = counterAnnotations[index]
            registerUndo(action: .removeCounter(counter))
            counterAnnotations.remove(at: index)
            nextCounterNumber = max(1, nextCounterNumber - 1)
            
        case .none:
            break
        }
    }
    
    // MARK: - Copy/Paste/Cut/Duplicate
    
    /// Copy selected objects to clipboard
    func copySelectedObjects() {
        guard !selectedObjects.isEmpty else { return }

        clipboard.removeAll()

        let sortedObjects = selectedObjects.sorted { obj1, obj2 in
            let (type1, idx1) = obj1.sortValue
            let (type2, idx2) = obj2.sortValue
            return type1 < type2 || (type1 == type2 && idx1 < idx2)
        }

        for object in sortedObjects {
            switch object {
            case .arrow(let index):
                guard index < arrows.count else { continue }
                clipboard.append(.arrow(arrows[index]))

            case .line(let index):
                guard index < lines.count else { continue }
                clipboard.append(.line(lines[index]))

            case .rectangle(let index):
                guard index < rectangles.count else { continue }
                clipboard.append(.rectangle(rectangles[index]))

            case .circle(let index):
                guard index < circles.count else { continue }
                clipboard.append(.circle(circles[index]))

            case .path(let index):
                guard index < paths.count else { continue }
                clipboard.append(.path(paths[index]))

            case .highlight(let index):
                guard index < highlightPaths.count else { continue }
                clipboard.append(.highlight(highlightPaths[index]))

            case .text(let index):
                guard index < textAnnotations.count else { continue }
                clipboard.append(.text(textAnnotations[index]))

            case .counter(let index):
                guard index < counterAnnotations.count else { continue }
                clipboard.append(.counter(counterAnnotations[index]))

            case .none:
                continue
            }
        }
    }
    
    /// Cut selected objects (copy + delete)
    func cutSelectedObjects() {
        guard !selectedObjects.isEmpty else { return }
        
        copySelectedObjects()
        deleteSelectedObjects()
    }
    
    /// Paste objects from clipboard at current cursor position
    func pasteObjects() {
        guard !clipboard.isEmpty else { return }
        
        // Get current mouse cursor position in window coordinates
        guard let window = window else { return }
        let screenLocation = NSEvent.mouseLocation
        let windowLocation = window.convertPoint(fromScreen: screenLocation)
        let cursorPosition = convert(windowLocation, from: nil)
        
        // Calculate the center of the clipboard objects
        let clipboardCenter = calculateClipboardCenter()
        
        // Calculate offset to move clipboard center to cursor position
        let offsetX = cursorPosition.x - clipboardCenter.x
        let offsetY = cursorPosition.y - clipboardCenter.y
        
        // Use internal paste method
        pasteObjectsWithOffset(offsetX: offsetX, offsetY: offsetY)
    }
    
    /// Internal method to paste objects with specific offset
    private func pasteObjectsWithOffset(offsetX: CGFloat, offsetY: CGFloat) {
        guard !clipboard.isEmpty else { return }

        var pastedObjects: [SelectedObject] = []

        for item in clipboard {
            switch item {
            case .arrow(var arrow):
                arrow.startPoint = NSPoint(x: arrow.startPoint.x + offsetX, y: arrow.startPoint.y + offsetY)
                arrow.endPoint = NSPoint(x: arrow.endPoint.x + offsetX, y: arrow.endPoint.y + offsetY)
                arrow.creationTime = fadeMode ? CACurrentMediaTime() : nil
                arrows.append(arrow)
                registerUndo(action: .addArrow(arrow))
                pastedObjects.append(.arrow(index: arrows.count - 1))

            case .line(var line):
                line.startPoint = NSPoint(x: line.startPoint.x + offsetX, y: line.startPoint.y + offsetY)
                line.endPoint = NSPoint(x: line.endPoint.x + offsetX, y: line.endPoint.y + offsetY)
                line.creationTime = fadeMode ? CACurrentMediaTime() : nil
                lines.append(line)
                registerUndo(action: .addLine(line))
                pastedObjects.append(.line(index: lines.count - 1))

            case .rectangle(var rect):
                rect.startPoint = NSPoint(x: rect.startPoint.x + offsetX, y: rect.startPoint.y + offsetY)
                rect.endPoint = NSPoint(x: rect.endPoint.x + offsetX, y: rect.endPoint.y + offsetY)
                rect.creationTime = fadeMode ? CACurrentMediaTime() : nil
                rectangles.append(rect)
                registerUndo(action: .addRectangle(rect))
                pastedObjects.append(.rectangle(index: rectangles.count - 1))

            case .circle(var circle):
                circle.startPoint = NSPoint(x: circle.startPoint.x + offsetX, y: circle.startPoint.y + offsetY)
                circle.endPoint = NSPoint(x: circle.endPoint.x + offsetX, y: circle.endPoint.y + offsetY)
                circle.creationTime = fadeMode ? CACurrentMediaTime() : nil
                circles.append(circle)
                registerUndo(action: .addCircle(circle))
                pastedObjects.append(.circle(index: circles.count - 1))

            case .path(var path):
                path.points = path.points.map { timedPoint in
                    TimedPoint(
                        point: NSPoint(x: timedPoint.point.x + offsetX, y: timedPoint.point.y + offsetY),
                        timestamp: fadeMode ? CACurrentMediaTime() : timedPoint.timestamp
                    )
                }
                paths.append(path)
                registerUndo(action: .addPath(path))
                pastedObjects.append(.path(index: paths.count - 1))

            case .highlight(var highlight):
                highlight.points = highlight.points.map { timedPoint in
                    TimedPoint(
                        point: NSPoint(x: timedPoint.point.x + offsetX, y: timedPoint.point.y + offsetY),
                        timestamp: fadeMode ? CACurrentMediaTime() : timedPoint.timestamp
                    )
                }
                highlightPaths.append(highlight)
                registerUndo(action: .addHighlight(highlight))
                pastedObjects.append(.highlight(index: highlightPaths.count - 1))

            case .text(var text):
                text.position = NSPoint(x: text.position.x + offsetX, y: text.position.y + offsetY)
                textAnnotations.append(text)
                registerUndo(action: .addText(text))
                pastedObjects.append(.text(index: textAnnotations.count - 1))

            case .counter(var counter):
                counter.position = NSPoint(x: counter.position.x + offsetX, y: counter.position.y + offsetY)
                counter.number = nextCounterNumber
                counter.creationTime = fadeMode ? CACurrentMediaTime() : nil
                counterAnnotations.append(counter)
                registerUndo(action: .addCounter(counter))
                pastedObjects.append(.counter(index: counterAnnotations.count - 1))
                nextCounterNumber += 1
            }
        }

        selectedObjects = Set(pastedObjects)
        currentTool = .select

        needsDisplay = true
    }
    
    /// Calculate the center point of objects in clipboard
    func calculateClipboardCenter() -> NSPoint {
        guard !clipboard.isEmpty else { return .zero }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for item in clipboard {
            switch item {
            case .arrow(let arrow):
                minX = min(minX, min(arrow.startPoint.x, arrow.endPoint.x))
                minY = min(minY, min(arrow.startPoint.y, arrow.endPoint.y))
                maxX = max(maxX, max(arrow.startPoint.x, arrow.endPoint.x))
                maxY = max(maxY, max(arrow.startPoint.y, arrow.endPoint.y))

            case .line(let line):
                minX = min(minX, min(line.startPoint.x, line.endPoint.x))
                minY = min(minY, min(line.startPoint.y, line.endPoint.y))
                maxX = max(maxX, max(line.startPoint.x, line.endPoint.x))
                maxY = max(maxY, max(line.startPoint.y, line.endPoint.y))

            case .rectangle(let rect):
                minX = min(minX, min(rect.startPoint.x, rect.endPoint.x))
                minY = min(minY, min(rect.startPoint.y, rect.endPoint.y))
                maxX = max(maxX, max(rect.startPoint.x, rect.endPoint.x))
                maxY = max(maxY, max(rect.startPoint.y, rect.endPoint.y))

            case .circle(let circle):
                minX = min(minX, min(circle.startPoint.x, circle.endPoint.x))
                minY = min(minY, min(circle.startPoint.y, circle.endPoint.y))
                maxX = max(maxX, max(circle.startPoint.x, circle.endPoint.x))
                maxY = max(maxY, max(circle.startPoint.y, circle.endPoint.y))

            case .path(let path):
                guard !path.points.isEmpty else { continue }
                for point in path.points {
                    minX = min(minX, point.point.x)
                    minY = min(minY, point.point.y)
                    maxX = max(maxX, point.point.x)
                    maxY = max(maxY, point.point.y)
                }

            case .highlight(let highlight):
                guard !highlight.points.isEmpty else { continue }
                for point in highlight.points {
                    minX = min(minX, point.point.x)
                    minY = min(minY, point.point.y)
                    maxX = max(maxX, point.point.x)
                    maxY = max(maxY, point.point.y)
                }

            case .text(let text):
                let estimatedWidth: CGFloat = CGFloat(text.text.count) * 8.0
                let estimatedHeight: CGFloat = 20.0
                minX = min(minX, text.position.x)
                minY = min(minY, text.position.y)
                maxX = max(maxX, text.position.x + estimatedWidth)
                maxY = max(maxY, text.position.y + estimatedHeight)

            case .counter(let counter):
                let radius: CGFloat = 15.0
                minX = min(minX, counter.position.x - radius)
                minY = min(minY, counter.position.y - radius)
                maxX = max(maxX, counter.position.x + radius)
                maxY = max(maxY, counter.position.y + radius)
            }
        }

        return NSPoint(x: (minX + maxX) / 2.0, y: (minY + maxY) / 2.0)
    }
    
    /// Duplicate selected objects with a small offset
    func duplicateSelectedObjects() {
        guard !selectedObjects.isEmpty else { return }
        
        // Save current selection to clipboard
        copySelectedObjects()
        
        // Calculate offset (20 pixels down and right)
        let duplicateOffset: CGFloat = 20.0
        let offsetX = duplicateOffset
        let offsetY = -duplicateOffset  // Negative for visual downward movement
        
        // Use internal paste method with fixed offset
        pasteObjectsWithOffset(offsetX: offsetX, offsetY: offsetY)
    }
    
    func selectAllObjects() {
        selectedObjects.removeAll()

        let objectCollections: [(count: Int, factory: (Int) -> SelectedObject)] = [
            (arrows.count, { .arrow(index: $0) }),
            (lines.count, { .line(index: $0) }),
            (paths.count, { .path(index: $0) }),
            (highlightPaths.count, { .highlight(index: $0) }),
            (rectangles.count, { .rectangle(index: $0) }),
            (circles.count, { .circle(index: $0) }),
            (textAnnotations.count, { .text(index: $0) }),
            (counterAnnotations.count, { .counter(index: $0) })
        ]

        for (count, factory) in objectCollections {
            for i in 0..<count {
                selectedObjects.insert(factory(i))
            }
        }

        needsDisplay = true
    }

    func createTextField(
        at point: NSPoint, withText existingText: String = "", width: CGFloat = 300
    ) {
        activeTextField = NSTextField(
            frame: NSRect(x: point.x, y: point.y, width: width, height: 24))
        if let textField = activeTextField {
            textField.font = NSFont.systemFont(ofSize: 18)

            let boardType = currentBoardType
            if boardType == .blackboard {
                textField.backgroundColor = NSColor.black.withAlphaComponent(0.3)
                textField.textColor = adaptColorForBoard(currentColor, boardType: boardType)
            } else {
                textField.backgroundColor = NSColor.white.withAlphaComponent(0.3)
                textField.textColor = adaptColorForBoard(currentColor, boardType: boardType)
            }

            textField.isBordered = false
            textField.isEditable = true
            textField.isSelectable = true
            textField.isBezeled = false
            textField.drawsBackground = true
            textField.usesSingleLineMode = false
            textField.cell?.wraps = false
            textField.cell?.truncatesLastVisibleLine = false
            textField.stringValue = existingText
            textField.target = self
            textField.delegate = self
            textField.action = #selector(finalizeTextAnnotation(_:))

            // Set initial size
            let size = existingText.size(withAttributes: [.font: textField.font!])
            textField.frame.size.width = max(width, size.width + 20)  // Add some padding
            textField.frame.size.height = max(24, size.height)

            self.addSubview(textField)
            textField.becomeFirstResponder()

            // Select all text if editing existing annotation
            if !existingText.isEmpty {
                textField.currentEditor()?.selectAll(nil)
            }
        }
    }

    @objc func finalizeTextAnnotation(_ sender: NSTextField) {
        guard let currentText = currentTextAnnotation else { return }
        let typedText = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let position = sender.frame.origin
        sender.removeFromSuperview()
        activeTextField = nil
        window?.makeFirstResponder(nil)

        if !typedText.isEmpty {
            let finalAnnotation = TextAnnotation(
                text: typedText,
                position: position,
                color: currentText.color,
                fontSize: currentText.fontSize
            )

            if let editingIndex = editingTextAnnotationIndex {
                if editingIndex < textAnnotations.count {
                    registerUndo(action: .removeText(textAnnotations[editingIndex]))
                    textAnnotations[editingIndex] = finalAnnotation
                    registerUndo(action: .addText(finalAnnotation))
                }
                editingTextAnnotationIndex = nil
            } else {
                registerUndo(action: .addText(finalAnnotation))
                textAnnotations.append(finalAnnotation)
            }
        } else if let editingIndex = editingTextAnnotationIndex {
            if editingIndex < textAnnotations.count {
                let oldAnnotation = textAnnotations[editingIndex]
                registerUndo(action: .removeText(oldAnnotation))
                textAnnotations.remove(at: editingIndex)
            }
            editingTextAnnotationIndex = nil
        }

        currentTextAnnotation = nil
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
        -> Bool
    {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if let textField = control as? NSTextField {
                finalizeTextAnnotation(textField)
            }
            return true
        } else if commandSelector == #selector(insertNewline(_:)) {
            if let textField = control as? NSTextField {
                finalizeTextAnnotation(textField)
            }
            return true
        }

        return false
    }

    func isAnythingFading() -> Bool {
        guard fadeMode else {
            return false
        }

        let now = CACurrentMediaTime()
        let stillFadingArrows = arrows.contains { arrow in
            if let creationTime = arrow.creationTime {
                return (now - creationTime) < fadeDuration
            }
            return false
        }

        let stillFadingLines = lines.contains { line in
            if let creationTime = line.creationTime {
                return (now - creationTime) < fadeDuration
            }
            return false
        }
        let stillFadingRectangles = rectangles.contains { rect in
            if let creationTime = rect.creationTime {
                return (now - creationTime) < fadeDuration
            }
            return false
        }
        let stillFadingCircles = circles.contains { circle in
            if let creationTime = circle.creationTime {
                return (now - creationTime) < fadeDuration
            }
            return false
        }

        let stillFadingCounters = counterAnnotations.contains { counter in
            if let creationTime = counter.creationTime {
                return (now - creationTime) < fadeDuration
            }
            return false
        }

        let maxPathAge =
            highlightPaths.contains { path in
                if let minTimestamp = path.points.map({ $0.timestamp }).min() {
                    return (now - minTimestamp) < fadeDuration
                }
                return false
            }
            || paths.contains { path in
                if let minTimestamp = path.points.map({ $0.timestamp }).min() {
                    return (now - minTimestamp) < fadeDuration
                }
                return false
            }

        return stillFadingArrows
            || stillFadingLines
            || stillFadingRectangles
            || stillFadingCircles
            || stillFadingCounters
            || maxPathAge
    }

    func adaptColorForBoard(_ color: NSColor, boardType: BoardView.BoardType) -> NSColor {
        return BoardManager.shared.adaptColor(color, forBoardType: boardType)
    }

    var currentBoardType: BoardView.BoardType {
        return BoardManager.shared.currentBoardType
    }

    func updateAdaptColors(boardEnabled: Bool) {
        adaptColorsToBoardType = boardEnabled
        needsDisplay = true
    }
    
    // MARK: - Selection and Hit Testing
    
    /// Find object at point, checking in reverse order (topmost/latest first)
    func findObjectAt(point: NSPoint) -> SelectedObject {
        // Check in reverse order - last drawn is on top
        
        // 1. Check counters
        for (index, counter) in counterAnnotations.enumerated().reversed() {
            if hitTestCounter(counter, point: point) {
                return .counter(index: index)
            }
        }
        
        // 2. Check text annotations
        for (index, text) in textAnnotations.enumerated().reversed() {
            if hitTestText(text, point: point) {
                return .text(index: index)
            }
        }
        
        // 3. Check circles
        for (index, circle) in circles.enumerated().reversed() {
            if hitTestCircle(circle, point: point) {
                return .circle(index: index)
            }
        }
        
        // 4. Check rectangles
        for (index, rect) in rectangles.enumerated().reversed() {
            if hitTestRectangle(rect, point: point) {
                return .rectangle(index: index)
            }
        }
        
        // 5. Check highlight paths
        for (index, path) in highlightPaths.enumerated().reversed() {
            if hitTestHighlightPath(path, point: point) {
                return .highlight(index: index)
            }
        }
        
        // 6. Check regular paths
        for (index, path) in paths.enumerated().reversed() {
            if hitTestPath(path, point: point) {
                return .path(index: index)
            }
        }
        
        // 7. Check lines
        for (index, line) in lines.enumerated().reversed() {
            if hitTestLine(line, point: point) {
                return .line(index: index)
            }
        }
        
        // 8. Check arrows
        for (index, arrow) in arrows.enumerated().reversed() {
            if hitTestArrow(arrow, point: point) {
                return .arrow(index: index)
            }
        }
        
        return .none
    }
    
    func findObjectsInRect(_ rect: NSRect) -> Set<SelectedObject> {
        var foundObjects = Set<SelectedObject>()

        let objectCollections: [(count: Int, factory: (Int) -> SelectedObject)] = [
            (counterAnnotations.count, { .counter(index: $0) }),
            (textAnnotations.count, { .text(index: $0) }),
            (circles.count, { .circle(index: $0) }),
            (rectangles.count, { .rectangle(index: $0) }),
            (highlightPaths.count, { .highlight(index: $0) }),
            (paths.count, { .path(index: $0) }),
            (lines.count, { .line(index: $0) }),
            (arrows.count, { .arrow(index: $0) })
        ]

        for (count, factory) in objectCollections {
            for i in 0..<count {
                let selectedObject = factory(i)
                if objectIntersectsRect(selectedObject, rect: rect) {
                    foundObjects.insert(selectedObject)
                }
            }
        }

        return foundObjects
    }
    
    /// Check if an object intersects with a rectangle
    private func objectIntersectsRect(_ object: SelectedObject, rect: NSRect) -> Bool {
        switch object {
        case .arrow(let index):
            guard index < arrows.count else { return false }
            let arrow = arrows[index]
            return lineSegmentIntersectsRect(start: arrow.startPoint, end: arrow.endPoint, rect: rect)
            
        case .line(let index):
            guard index < lines.count else { return false }
            let line = lines[index]
            return lineSegmentIntersectsRect(start: line.startPoint, end: line.endPoint, rect: rect)
            
        case .rectangle(let index):
            guard index < rectangles.count else { return false }
            let r = rectangles[index]
            let objRect = NSRect(
                x: min(r.startPoint.x, r.endPoint.x),
                y: min(r.startPoint.y, r.endPoint.y),
                width: abs(r.endPoint.x - r.startPoint.x),
                height: abs(r.endPoint.y - r.startPoint.y)
            )
            return rect.intersects(objRect)
            
        case .circle(let index):
            guard index < circles.count else { return false }
            let c = circles[index]
            let circleRect = NSRect(
                x: min(c.startPoint.x, c.endPoint.x),
                y: min(c.startPoint.y, c.endPoint.y),
                width: abs(c.endPoint.x - c.startPoint.x),
                height: abs(c.endPoint.y - c.startPoint.y)
            )
            return rect.intersects(circleRect)
            
        case .path(let index):
            guard index < paths.count else { return false }
            let path = paths[index]
            for point in path.points {
                if rect.contains(point.point) {
                    return true
                }
            }
            return false
            
        case .highlight(let index):
            guard index < highlightPaths.count else { return false }
            let path = highlightPaths[index]
            for point in path.points {
                if rect.contains(point.point) {
                    return true
                }
            }
            return false
            
        case .text(let index):
            guard index < textAnnotations.count else { return false }
            let textRect = getTextRect(for: textAnnotations[index])
            return rect.intersects(textRect)
            
        case .counter(let index):
            guard index < counterAnnotations.count else { return false }
            return rect.contains(counterAnnotations[index].position)
            
        case .none:
            return false
        }
    }
    
    /// Check if a line segment intersects with a rectangle
    private func lineSegmentIntersectsRect(start: NSPoint, end: NSPoint, rect: NSRect) -> Bool {
        // Check if either endpoint is inside the rectangle
        if rect.contains(start) || rect.contains(end) {
            return true
        }
        
        // Check if line intersects any edge of the rectangle
        let edges = [
            (NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY)), // Bottom
            (NSPoint(x: rect.maxX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.maxY)), // Right
            (NSPoint(x: rect.maxX, y: rect.maxY), NSPoint(x: rect.minX, y: rect.maxY)), // Top
            (NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.minX, y: rect.minY))  // Left
        ]
        
        for (edgeStart, edgeEnd) in edges {
            if lineSegmentsIntersect(p1: start, p2: end, p3: edgeStart, p4: edgeEnd) {
                return true
            }
        }
        
        return false
    }
    
    /// Check if two line segments intersect
    private func lineSegmentsIntersect(p1: NSPoint, p2: NSPoint, p3: NSPoint, p4: NSPoint) -> Bool {
        let d = (p2.x - p1.x) * (p4.y - p3.y) - (p2.y - p1.y) * (p4.x - p3.x)
        if abs(d) < 0.001 { return false } // Parallel lines
        
        let t = ((p3.x - p1.x) * (p4.y - p3.y) - (p3.y - p1.y) * (p4.x - p3.x)) / d
        let u = ((p3.x - p1.x) * (p2.y - p1.y) - (p3.y - p1.y) * (p2.x - p1.x)) / d
        
        return t >= 0 && t <= 1 && u >= 0 && u <= 1
    }
    
    // MARK: - Hit Test Methods
    
    private func hitTestLine(_ line: Line, point: NSPoint) -> Bool {
        let baseTolerance = line.lineWidth / 2.0
        let minClickableTolerance: CGFloat = 5.0
        let tolerance = max(baseTolerance, minClickableTolerance)
        
        return distanceFromPointToLineSegment(
            point: point,
            lineStart: line.startPoint,
            lineEnd: line.endPoint
        ) <= tolerance
    }
    
    private func hitTestArrow(_ arrow: Arrow, point: NSPoint) -> Bool {
        let baseTolerance = arrow.lineWidth / 2.0
        let minClickableTolerance: CGFloat = 5.0
        let tolerance = max(baseTolerance, minClickableTolerance)
        
        // Check the main line
        let lineDistance = distanceFromPointToLineSegment(
            point: point,
            lineStart: arrow.startPoint,
            lineEnd: arrow.endPoint
        )
        
        if lineDistance <= tolerance {
            return true
        }
        
        // Also check if point is inside the arrowhead triangle
        let sideLength: CGFloat = max(10.0, arrow.lineWidth * 4.0)
        let dx = arrow.endPoint.x - arrow.startPoint.x
        let dy = arrow.endPoint.y - arrow.startPoint.y
        let angle = atan2(dy, dx)
        let height = sideLength * sqrt(3.0) / 2.0
        let halfBase = sideLength / 2.0
        
        let baseCenter = NSPoint(
            x: arrow.endPoint.x - height * cos(angle),
            y: arrow.endPoint.y - height * sin(angle)
        )
        
        let perpAngle = angle + .pi / 2
        let p1 = NSPoint(
            x: baseCenter.x + halfBase * cos(perpAngle),
            y: baseCenter.y + halfBase * sin(perpAngle)
        )
        let p2 = NSPoint(
            x: baseCenter.x - halfBase * cos(perpAngle),
            y: baseCenter.y - halfBase * sin(perpAngle)
        )
        
        return isPointInTriangle(point: point, v1: arrow.endPoint, v2: p1, v3: p2)
    }
    
    private func hitTestPath(_ path: DrawingPath, point: NSPoint) -> Bool {
        guard path.points.count >= 2 else {
            if path.points.count == 1 {
                let baseTolerance = path.lineWidth / 2.0
                let minClickableTolerance: CGFloat = 5.0
                let tolerance = max(baseTolerance, minClickableTolerance)
                
                let dx = point.x - path.points[0].point.x
                let dy = point.y - path.points[0].point.y
                return sqrt(dx * dx + dy * dy) <= tolerance
            }
            return false
        }
        
        let baseTolerance = path.lineWidth / 2.0
        let minClickableTolerance: CGFloat = 5.0
        let tolerance = max(baseTolerance, minClickableTolerance)
        
        for i in 0..<(path.points.count - 1) {
            let distance = distanceFromPointToLineSegment(
                point: point,
                lineStart: path.points[i].point,
                lineEnd: path.points[i + 1].point
            )
            if distance <= tolerance {
                return true
            }
        }
        return false
    }
    
    private func hitTestHighlightPath(_ path: DrawingPath, point: NSPoint) -> Bool {
        guard path.points.count >= 2 else {
            if path.points.count == 1 {
                let highlighterWidth = path.lineWidth * 4.67
                let baseTolerance = highlighterWidth / 2.0
                let minClickableTolerance: CGFloat = 5.0
                let tolerance = max(baseTolerance, minClickableTolerance)
                
                let dx = point.x - path.points[0].point.x
                let dy = point.y - path.points[0].point.y
                return sqrt(dx * dx + dy * dy) <= tolerance
            }
            return false
        }
        
        let highlighterWidth = path.lineWidth * 4.67
        let baseTolerance = highlighterWidth / 2.0
        let minClickableTolerance: CGFloat = 5.0
        let tolerance = max(baseTolerance, minClickableTolerance)
        
        for i in 0..<(path.points.count - 1) {
            let distance = distanceFromPointToLineSegment(
                point: point,
                lineStart: path.points[i].point,
                lineEnd: path.points[i + 1].point
            )
            if distance <= tolerance {
                return true
            }
        }
        return false
    }
    
    private func hitTestRectangle(_ rect: Rectangle, point: NSPoint) -> Bool {
        let bounds = NSRect(
            x: min(rect.startPoint.x, rect.endPoint.x),
            y: min(rect.startPoint.y, rect.endPoint.y),
            width: abs(rect.endPoint.x - rect.startPoint.x),
            height: abs(rect.endPoint.y - rect.startPoint.y)
        )
        
        // Only check edges (not inside)
        let baseTolerance = rect.lineWidth / 2.0
        let minClickableTolerance: CGFloat = 5.0
        let edgeTolerance = max(baseTolerance, minClickableTolerance)
        
        // Expand and shrink to create edge zone
        let outerBounds = bounds.insetBy(dx: -edgeTolerance, dy: -edgeTolerance)
        let innerBounds = bounds.insetBy(dx: edgeTolerance, dy: edgeTolerance)
        
        // Point is on edge if it's in outer but not in inner
        return outerBounds.contains(point) && !innerBounds.contains(point)
    }
    
    private func hitTestCircle(_ circle: Circle, point: NSPoint) -> Bool {
        let bounds = NSRect(
            x: min(circle.startPoint.x, circle.endPoint.x),
            y: min(circle.startPoint.y, circle.endPoint.y),
            width: abs(circle.endPoint.x - circle.startPoint.x),
            height: abs(circle.endPoint.y - circle.startPoint.y)
        )
        
        let centerX = bounds.midX
        let centerY = bounds.midY
        let radiusX = bounds.width / 2
        let radiusY = bounds.height / 2
        
        let dx = (point.x - centerX) / radiusX
        let dy = (point.y - centerY) / radiusY
        let normalizedDistance = sqrt(dx * dx + dy * dy)
        
        // Only check edge/perimeter (not inside)
        let baseTolerance = circle.lineWidth / 2.0
        let minClickableTolerance: CGFloat = 5.0
        let edgeTolerance = max(baseTolerance, minClickableTolerance)
        
        let toleranceNormalized = edgeTolerance / min(radiusX, radiusY)
        
        // Point is on edge if distance is between (1.0 - tolerance) and (1.0 + tolerance)
        let innerBoundary = max(0, 1.0 - toleranceNormalized)
        let outerBoundary = 1.0 + toleranceNormalized
        
        return normalizedDistance >= innerBoundary && normalizedDistance <= outerBoundary
    }
    
    private func hitTestText(_ text: TextAnnotation, point: NSPoint) -> Bool {
        let textRect = getTextRect(for: text)
        return textRect.contains(point)
    }
    
    private func getTextRect(for annotation: TextAnnotation) -> NSRect {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: annotation.fontSize)
        ]
        let size = annotation.text.size(withAttributes: attributes)
        return NSRect(
            x: annotation.position.x,
            y: annotation.position.y,
            width: size.width + 20,
            height: size.height + 10
        )
    }
    
    private func hitTestCounter(_ counter: CounterAnnotation, point: NSPoint) -> Bool {
        let radius: CGFloat = 15.0
        let dx = point.x - counter.position.x
        let dy = point.y - counter.position.y
        let distance = sqrt(dx * dx + dy * dy)
        return distance <= radius
    }
    
    // MARK: - Helper Methods
    
    private func isPointInTriangle(point: NSPoint, v1: NSPoint, v2: NSPoint, v3: NSPoint) -> Bool {
        let denominator = ((v2.y - v3.y) * (v1.x - v3.x) + (v3.x - v2.x) * (v1.y - v3.y))
        guard denominator != 0 else { return false }
        
        let a = ((v2.y - v3.y) * (point.x - v3.x) + (v3.x - v2.x) * (point.y - v3.y)) / denominator
        let b = ((v3.y - v1.y) * (point.x - v3.x) + (v1.x - v3.x) * (point.y - v3.y)) / denominator
        let c = 1 - a - b
        
        return a >= 0 && a <= 1 && b >= 0 && b <= 1 && c >= 0 && c <= 1
    }
    
    private func distanceFromPointToLineSegment(point: NSPoint, lineStart: NSPoint, lineEnd: NSPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSquared = dx * dx + dy * dy
        
        if lengthSquared == 0 {
            let pdx = point.x - lineStart.x
            let pdy = point.y - lineStart.y
            return sqrt(pdx * pdx + pdy * pdy)
        }
        
        var t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        
        let nearestX = lineStart.x + t * dx
        let nearestY = lineStart.y + t * dy
        
        let pdx = point.x - nearestX
        let pdy = point.y - nearestY
        return sqrt(pdx * pdx + pdy * pdy)
    }

    // MARK: - Eraser Logic

    func eraseAtPoint(_ point: NSPoint) {
        var deletedPaths: [DrawingPath] = []
        var deletedArrows: [Arrow] = []
        var deletedLines: [Line] = []
        var deletedHighlights: [DrawingPath] = []
        var deletedRectangles: [Rectangle] = []
        var deletedCircles: [Circle] = []
        var deletedTextAnnotations: [TextAnnotation] = []
        var deletedCounters: [CounterAnnotation] = []

        // Check pen paths
        for (index, path) in paths.enumerated().reversed() {
            if pathIntersectsPoint(path, point: point, radius: eraserRadius) {
                deletedPaths.append(path)
                paths.remove(at: index)
            }
        }

        // Check highlighter paths
        for (index, path) in highlightPaths.enumerated().reversed() {
            if pathIntersectsPoint(path, point: point, radius: eraserRadius) {
                deletedHighlights.append(path)
                highlightPaths.remove(at: index)
            }
        }

        // Check arrows
        for (index, arrow) in arrows.enumerated().reversed() {
            if lineIntersectsPoint(arrow.startPoint, arrow.endPoint, point: point, radius: eraserRadius) {
                deletedArrows.append(arrow)
                arrows.remove(at: index)
            }
        }

        // Check lines
        for (index, line) in lines.enumerated().reversed() {
            if lineIntersectsPoint(line.startPoint, line.endPoint, point: point, radius: eraserRadius) {
                deletedLines.append(line)
                lines.remove(at: index)
            }
        }

        // Check rectangles
        for (index, rectangle) in rectangles.enumerated().reversed() {
            if rectangleIntersectsPoint(rectangle, point: point, radius: eraserRadius) {
                deletedRectangles.append(rectangle)
                rectangles.remove(at: index)
            }
        }

        // Check circles
        for (index, circle) in circles.enumerated().reversed() {
            if circleIntersectsPoint(circle, point: point, radius: eraserRadius) {
                deletedCircles.append(circle)
                circles.remove(at: index)
            }
        }

        // Check text annotations
        for (index, text) in textAnnotations.enumerated().reversed() {
            if textIntersectsPoint(text, point: point, radius: eraserRadius) {
                deletedTextAnnotations.append(text)
                textAnnotations.remove(at: index)
            }
        }

        // Check counter annotations
        for (index, counter) in counterAnnotations.enumerated().reversed() {
            if counterIntersectsPoint(counter, point: point, radius: eraserRadius) {
                deletedCounters.append(counter)
                counterAnnotations.remove(at: index)
            }
        }

        // Register undo only if something was deleted
        if !deletedPaths.isEmpty || !deletedArrows.isEmpty || !deletedLines.isEmpty ||
            !deletedHighlights.isEmpty || !deletedRectangles.isEmpty || !deletedCircles.isEmpty ||
            !deletedTextAnnotations.isEmpty || !deletedCounters.isEmpty {

            registerUndo(action: .eraseAnnotations(
                deletedPaths, deletedArrows, deletedLines, deletedHighlights,
                deletedRectangles, deletedCircles, deletedTextAnnotations, deletedCounters
            ))
        }
    }

    private func pathIntersectsPoint(_ path: DrawingPath, point: NSPoint, radius: CGFloat) -> Bool {
        for timedPoint in path.points {
            let distance = hypot(timedPoint.point.x - point.x, timedPoint.point.y - point.y)
            if distance <= radius {
                return true
            }
        }
        return false
    }

    private func lineIntersectsPoint(_ start: NSPoint, _ end: NSPoint, point: NSPoint, radius: CGFloat) -> Bool {
        let distance = distanceFromPointToLineSegment(point: point, lineStart: start, lineEnd: end)
        return distance <= radius
    }

    private func rectangleIntersectsPoint(_ rectangle: Rectangle, point: NSPoint, radius: CGFloat) -> Bool {
        // Check if point is near any of the four edges
        let bounds = NSRect(
            x: min(rectangle.startPoint.x, rectangle.endPoint.x),
            y: min(rectangle.startPoint.y, rectangle.endPoint.y),
            width: abs(rectangle.endPoint.x - rectangle.startPoint.x),
            height: abs(rectangle.endPoint.y - rectangle.startPoint.y)
        )

        let topLeft = NSPoint(x: bounds.minX, y: bounds.minY)
        let topRight = NSPoint(x: bounds.maxX, y: bounds.minY)
        let bottomLeft = NSPoint(x: bounds.minX, y: bounds.maxY)
        let bottomRight = NSPoint(x: bounds.maxX, y: bounds.maxY)

        return lineIntersectsPoint(topLeft, topRight, point: point, radius: radius) ||
               lineIntersectsPoint(topRight, bottomRight, point: point, radius: radius) ||
               lineIntersectsPoint(bottomRight, bottomLeft, point: point, radius: radius) ||
               lineIntersectsPoint(bottomLeft, topLeft, point: point, radius: radius)
    }

    private func circleIntersectsPoint(_ circle: Circle, point: NSPoint, radius: CGFloat) -> Bool {
        let bounds = NSRect(
            x: min(circle.startPoint.x, circle.endPoint.x),
            y: min(circle.startPoint.y, circle.endPoint.y),
            width: abs(circle.endPoint.x - circle.startPoint.x),
            height: abs(circle.endPoint.y - circle.startPoint.y)
        )

        let centerX = bounds.midX
        let centerY = bounds.midY
        let radiusX = bounds.width / 2
        let radiusY = bounds.height / 2

        // Distance from point to ellipse edge (approximate)
        let dx = point.x - centerX
        let dy = point.y - centerY
        let normalizedDist = sqrt((dx * dx) / (radiusX * radiusX) + (dy * dy) / (radiusY * radiusY))
        let edgeDistance = abs(normalizedDist - 1.0) * min(radiusX, radiusY)

        return edgeDistance <= radius
    }

    private func textIntersectsPoint(_ text: TextAnnotation, point: NSPoint, radius: CGFloat) -> Bool {
        let textRect = getTextRect(for: text)
        let expandedRect = textRect.insetBy(dx: -radius, dy: -radius)
        return expandedRect.contains(point)
    }

    private func counterIntersectsPoint(_ counter: CounterAnnotation, point: NSPoint, radius: CGFloat) -> Bool {
        let counterRadius: CGFloat = 15.0
        let dx = point.x - counter.position.x
        let dy = point.y - counter.position.y
        let distance = sqrt(dx * dx + dy * dy)
        return distance <= (counterRadius + radius)
    }

    // MARK: - Object Movement
    
    func moveSelectedObjects(by delta: NSPoint) {
        for selectedObj in selectedObjects {
            moveObject(selectedObj, by: delta)
        }
    }
    
    private func moveObject(_ object: SelectedObject, by delta: NSPoint) {
        switch object {
        case .arrow(let index):
            guard index < arrows.count else { return }
            arrows[index].startPoint.x += delta.x
            arrows[index].startPoint.y += delta.y
            arrows[index].endPoint.x += delta.x
            arrows[index].endPoint.y += delta.y
            
        case .line(let index):
            guard index < lines.count else { return }
            lines[index].startPoint.x += delta.x
            lines[index].startPoint.y += delta.y
            lines[index].endPoint.x += delta.x
            lines[index].endPoint.y += delta.y
            
        case .rectangle(let index):
            guard index < rectangles.count else { return }
            rectangles[index].startPoint.x += delta.x
            rectangles[index].startPoint.y += delta.y
            rectangles[index].endPoint.x += delta.x
            rectangles[index].endPoint.y += delta.y
            
        case .circle(let index):
            guard index < circles.count else { return }
            circles[index].startPoint.x += delta.x
            circles[index].startPoint.y += delta.y
            circles[index].endPoint.x += delta.x
            circles[index].endPoint.y += delta.y
            
        case .path(let index):
            guard index < paths.count else { return }
            for i in 0..<paths[index].points.count {
                paths[index].points[i].point.x += delta.x
                paths[index].points[i].point.y += delta.y
            }
            
        case .highlight(let index):
            guard index < highlightPaths.count else { return }
            for i in 0..<highlightPaths[index].points.count {
                highlightPaths[index].points[i].point.x += delta.x
                highlightPaths[index].points[i].point.y += delta.y
            }
            
        case .text(let index):
            guard index < textAnnotations.count else { return }
            textAnnotations[index].position.x += delta.x
            textAnnotations[index].position.y += delta.y
            
        case .counter(let index):
            guard index < counterAnnotations.count else { return }
            counterAnnotations[index].position.x += delta.x
            counterAnnotations[index].position.y += delta.y
            
        case .none:
            break
        }
    }
    
    func getObjectPosition(_ object: SelectedObject) -> Any? {
        switch object {
        case .arrow(let index):
            guard index < arrows.count else { return nil }
            return (arrows[index].startPoint, arrows[index].endPoint)
        case .line(let index):
            guard index < lines.count else { return nil }
            return (lines[index].startPoint, lines[index].endPoint)
        case .rectangle(let index):
            guard index < rectangles.count else { return nil }
            return (rectangles[index].startPoint, rectangles[index].endPoint)
        case .circle(let index):
            guard index < circles.count else { return nil }
            return (circles[index].startPoint, circles[index].endPoint)
        case .text(let index):
            guard index < textAnnotations.count else { return nil }
            return textAnnotations[index].position
        case .counter(let index):
            guard index < counterAnnotations.count else { return nil }
            return counterAnnotations[index].position
        case .path(let index):
            guard index < paths.count else { return nil }
            return paths[index].points.map { $0.point }
        case .highlight(let index):
            guard index < highlightPaths.count else { return nil }
            return highlightPaths[index].points.map { $0.point }
        case .none:
            return nil
        }
    }
    
    func registerMoveUndo(object: SelectedObject, from oldPos: Any, to newPos: Any) {
        switch object {
        case .arrow(let index):
            if let oldPositions = oldPos as? (NSPoint, NSPoint),
               let newPositions = newPos as? (NSPoint, NSPoint) {
                registerUndo(action: .moveArrow(index, oldPositions.0, oldPositions.1, newPositions.0, newPositions.1))
            }
        case .line(let index):
            if let oldPositions = oldPos as? (NSPoint, NSPoint),
               let newPositions = newPos as? (NSPoint, NSPoint) {
                registerUndo(action: .moveLine(index, oldPositions.0, oldPositions.1, newPositions.0, newPositions.1))
            }
        case .rectangle(let index):
            if let oldPositions = oldPos as? (NSPoint, NSPoint),
               let newPositions = newPos as? (NSPoint, NSPoint) {
                registerUndo(action: .moveRectangle(index, oldPositions.0, oldPositions.1, newPositions.0, newPositions.1))
            }
        case .circle(let index):
            if let oldPositions = oldPos as? (NSPoint, NSPoint),
               let newPositions = newPos as? (NSPoint, NSPoint) {
                registerUndo(action: .moveCircle(index, oldPositions.0, oldPositions.1, newPositions.0, newPositions.1))
            }
        case .text(let index):
            if let oldPosition = oldPos as? NSPoint,
               let newPosition = newPos as? NSPoint {
                registerUndo(action: .moveText(index, oldPosition, newPosition))
            }
        case .counter(let index):
            if let oldPosition = oldPos as? NSPoint,
               let newPosition = newPos as? NSPoint {
                registerUndo(action: .moveCounter(index, oldPosition, newPosition))
            }
        case .path(let index):
            if let oldPoints = oldPos as? [NSPoint],
               let newPoints = newPos as? [NSPoint],
               oldPoints.count == newPoints.count && oldPoints.count > 0 {
                let delta = NSPoint(
                    x: newPoints[0].x - oldPoints[0].x,
                    y: newPoints[0].y - oldPoints[0].y
                )
                registerUndo(action: .movePath(index, delta))
            }
        case .highlight(let index):
            if let oldPoints = oldPos as? [NSPoint],
               let newPoints = newPos as? [NSPoint],
               oldPoints.count == newPoints.count && oldPoints.count > 0 {
                let delta = NSPoint(
                    x: newPoints[0].x - oldPoints[0].x,
                    y: newPoints[0].y - oldPoints[0].y
                )
                registerUndo(action: .moveHighlight(index, delta))
            }
        case .none:
            break
        }
    }
    
    // MARK: - Selection Visual Feedback
    
}
