import Cocoa

class OverlayView: NSView, NSTextFieldDelegate {
    var arrows: [Arrow] = []
    var currentArrow: Arrow?

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

    var currentColor: NSColor = .systemRed
    var currentTool: ToolType = .pen

    var fadeMode: Bool = true
    let fadeDuration: CFTimeInterval = 1.25

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
        switch action {
        case .addPath(let path):
            undoManager?.registerUndo(withTarget: self) { target in
                if !target.paths.isEmpty {
                    target.paths.removeLast()
                    target.registerUndo(action: .removePath(path))
                    target.needsDisplay = true
                }
            }
        case .addArrow(let arrow):
            undoManager?.registerUndo(withTarget: self) { target in
                if !target.arrows.isEmpty {
                    target.arrows.removeLast()
                    target.registerUndo(action: .removeArrow(arrow))
                    target.needsDisplay = true
                }
            }
        case .addHighlight(let highlight):
            undoManager?.registerUndo(withTarget: self) { target in
                if !target.highlightPaths.isEmpty {
                    target.highlightPaths.removeLast()
                    target.registerUndo(action: .removeHighlight(highlight))
                    target.needsDisplay = true
                }
            }
        case .removePath(let path):
            undoManager?.registerUndo(withTarget: self) { target in
                target.paths.append(path)
                target.registerUndo(action: .addPath(path))
                target.needsDisplay = true
            }
        case .removeArrow(let arrow):
            undoManager?.registerUndo(withTarget: self) { target in
                target.arrows.append(arrow)
                target.registerUndo(action: .addArrow(arrow))
                target.needsDisplay = true
            }
        case .removeHighlight(let highlight):
            undoManager?.registerUndo(withTarget: self) { target in
                target.highlightPaths.append(highlight)
                target.registerUndo(action: .addHighlight(highlight))
                target.needsDisplay = true
            }
        case .addRectangle(let rectangle):
            undoManager?.registerUndo(withTarget: self) { target in
                if !target.rectangles.isEmpty {
                    target.rectangles.removeLast()
                    target.registerUndo(action: .removeRectangle(rectangle))
                    target.needsDisplay = true
                }
            }
        case .removeRectangle(let rectangle):
            undoManager?.registerUndo(withTarget: self) { target in
                target.rectangles.append(rectangle)
                target.registerUndo(action: .addRectangle(rectangle))
                target.needsDisplay = true
            }
        case .addCircle(let circle):
            undoManager?.registerUndo(withTarget: self) { target in
                if !target.circles.isEmpty {
                    target.circles.removeLast()
                    target.registerUndo(action: .removeCircle(circle))
                    target.needsDisplay = true
                }
            }
        case .removeCircle(let circle):
            undoManager?.registerUndo(withTarget: self) { target in
                target.circles.append(circle)
                target.registerUndo(action: .addCircle(circle))
                target.needsDisplay = true
            }
        case .addText(let annotation):
            undoManager?.registerUndo(withTarget: self) { target in
                if !target.textAnnotations.isEmpty {
                    target.textAnnotations.removeLast()
                    target.registerUndo(action: .removeText(annotation))
                    target.needsDisplay = true
                }
            }
        case .removeText(let annotation):
            undoManager?.registerUndo(withTarget: self) { target in
                target.textAnnotations.append(annotation)
                target.registerUndo(action: .addText(annotation))
                target.needsDisplay = true
            }
        case .moveText(let index, let oldPosition, let newPosition):
            undoManager?.registerUndo(withTarget: self) { target in
                target.textAnnotations[index].position = oldPosition
                target.registerUndo(action: .moveText(index, newPosition, oldPosition))
                target.needsDisplay = true
            }
        case .clearAll(
            let paths, let arrows, let highlights, let rectangles, let circles, let textAnnotations):
            undoManager?.registerUndo(withTarget: self) { target in
                target.paths = paths
                target.arrows = arrows
                target.highlightPaths = highlights
                target.rectangles = rectangles
                target.circles = circles
                target.textAnnotations = textAnnotations
                target.registerUndo(action: .clearAll([], [], [], [], [], []))
                target.needsDisplay = true
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
                        color: arrow.color.withAlphaComponent(alpha)
                    )
                    aliveArrows.append(arrow)
                }
            } else {
                drawArrow(from: arrow.startPoint, to: arrow.endPoint, color: arrow.color)
                aliveArrows.append(arrow)
            }
        }
        arrows = aliveArrows

        // Draw current arrow being drawn
        if let arrow = currentArrow {
            drawArrow(from: arrow.startPoint, to: arrow.endPoint, color: arrow.color)
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
            line.lineWidth = isHighlighter ? 14.0 : 3.0
            line.lineJoinStyle = .round
            line.lineCapStyle = .round
            line.stroke()
        }

        return validPoints
    }

    private func drawArrow(from start: NSPoint, to end: NSPoint, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)

        // Calculate arrow head
        let arrowLength: CGFloat = 25.0
        let arrowAngle: CGFloat = .pi / 6

        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)

        let p1 = NSPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        let p2 = NSPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )

        path.move(to: end)
        path.line(to: p1)
        path.move(to: end)
        path.line(to: p2)

        color.setStroke()
        path.lineWidth = 3.0
        path.stroke()
    }

    private func drawRectangle(_ rectangle: Rectangle, alpha: CGFloat) {
        let rect = NSRect(
            x: min(rectangle.startPoint.x, rectangle.endPoint.x),
            y: min(rectangle.startPoint.y, rectangle.endPoint.y),
            width: abs(rectangle.endPoint.x - rectangle.startPoint.x),
            height: abs(rectangle.endPoint.y - rectangle.startPoint.y)
        )

        let path = NSBezierPath(rect: rect)
        rectangle.color.withAlphaComponent(alpha).setStroke()
        path.lineWidth = 3.0
        path.stroke()
    }

    private func drawCircle(_ circle: Circle, alpha: CGFloat) {
        let rect = NSRect(
            x: min(circle.startPoint.x, circle.endPoint.x),
            y: min(circle.startPoint.y, circle.endPoint.y),
            width: abs(circle.endPoint.x - circle.startPoint.x),
            height: abs(circle.endPoint.y - circle.startPoint.y)
        )

        let path = NSBezierPath(ovalIn: rect)
        circle.color.withAlphaComponent(alpha).setStroke()
        path.lineWidth = 3.0
        path.stroke()
    }

    func clearArrows() {
        arrows.removeAll()
        currentArrow = nil
        needsDisplay = true
    }

    private func drawPath(_ path: DrawingPath, tool: ToolType) {
        guard !path.points.isEmpty else { return }

        let bezierPath = NSBezierPath()
        bezierPath.move(to: path.points[0].point)

        for timedPoint in path.points.dropFirst() {
            bezierPath.line(to: timedPoint.point)
        }

        if tool == .highlighter {
            path.color.withAlphaComponent(0.5).setStroke()
            bezierPath.lineWidth = 14.0
        } else {
            path.color.setStroke()
            bezierPath.lineWidth = 3.0
        }

        bezierPath.lineJoinStyle = .round
        bezierPath.lineCapStyle = .round
        bezierPath.stroke()
    }

    private func drawText(_ annotation: TextAnnotation) {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: annotation.color,
            .font: NSFont.systemFont(ofSize: annotation.fontSize),
        ]
        let attributedString = NSAttributedString(string: annotation.text, attributes: attributes)
        attributedString.draw(at: annotation.position)
    }

    func clearAll() {
        // Only register undo if there's something to clear
        if !paths.isEmpty || !arrows.isEmpty || !highlightPaths.isEmpty || !rectangles.isEmpty
            || !circles.isEmpty || !textAnnotations.isEmpty
        {
            let oldPaths = paths
            let oldArrows = arrows
            let oldHighlights = highlightPaths
            let oldRectangles = rectangles
            let oldCircles = circles
            let oldTextAnnotations = textAnnotations
            registerUndo(
                action: .clearAll(
                    oldPaths, oldArrows, oldHighlights, oldRectangles, oldCircles,
                    oldTextAnnotations))

            paths.removeAll()
            arrows.removeAll()
            highlightPaths.removeAll()
            rectangles.removeAll()
            circles.removeAll()
            textAnnotations.removeAll()
            currentArrow = nil
            currentPath = nil
            currentHighlight = nil
            currentRectangle = nil
            currentCircle = nil
            currentTextAnnotation = nil
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
            textField.backgroundColor = .clear
            textField.isBordered = false
            textField.textColor = currentColor
            textField.isEditable = true
            textField.isSelectable = true
            textField.isBezeled = false
            textField.drawsBackground = false
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

        // For pen/highlighter paths, you track fading by each TimedPoint.
        // If you keep them in memory until they fully fade, you can do something like:
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
            || stillFadingRectangles
            || stillFadingCircles
            || maxPathAge
    }
}
