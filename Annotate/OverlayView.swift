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
        switch action {
        case .addPath(let path):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    if !target.paths.isEmpty {
                        target.paths.removeLast()
                        target.registerUndo(action: .removePath(path))
                        target.needsDisplay = true
                    }
                }
            }
        case .addArrow(let arrow):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    if !target.arrows.isEmpty {
                        target.arrows.removeLast()
                        target.registerUndo(action: .removeArrow(arrow))
                        target.needsDisplay = true
                    }
                }
            }
        case .addLine(let line):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    if !target.lines.isEmpty {
                        target.lines.removeLast()
                        target.registerUndo(action: .removeLine(line))
                        target.needsDisplay = true
                    }
                }
            }
        case .addHighlight(let highlight):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    if !target.highlightPaths.isEmpty {
                        target.highlightPaths.removeLast()
                        target.registerUndo(action: .removeHighlight(highlight))
                        target.needsDisplay = true
                    }
                }
            }
        case .removePath(let path):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    target.paths.append(path)
                    target.registerUndo(action: .addPath(path))
                    target.needsDisplay = true
                }
            }
        case .removeArrow(let arrow):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    target.arrows.append(arrow)
                    target.registerUndo(action: .addArrow(arrow))
                    target.needsDisplay = true
                }
            }
        case .removeLine(let line):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    target.lines.append(line)
                    target.registerUndo(action: .addLine(line))
                    target.needsDisplay = true
                }
            }
        case .removeHighlight(let highlight):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    target.highlightPaths.append(highlight)
                    target.registerUndo(action: .addHighlight(highlight))
                    target.needsDisplay = true
                }
            }
        case .addRectangle(let rectangle):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    if !target.rectangles.isEmpty {
                        target.rectangles.removeLast()
                        target.registerUndo(action: .removeRectangle(rectangle))
                        target.needsDisplay = true
                    }
                }
            }
        case .removeRectangle(let rectangle):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    target.rectangles.append(rectangle)
                    target.registerUndo(action: .addRectangle(rectangle))
                    target.needsDisplay = true
                }
            }
        case .addCircle(let circle):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    if !target.circles.isEmpty {
                        target.circles.removeLast()
                        target.registerUndo(action: .removeCircle(circle))
                        target.needsDisplay = true
                    }
                }
            }
        case .removeCircle(let circle):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    target.circles.append(circle)
                    target.registerUndo(action: .addCircle(circle))
                    target.needsDisplay = true
                }
            }
        case .addText(let annotation):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    if !target.textAnnotations.isEmpty {
                        target.textAnnotations.removeLast()
                        target.registerUndo(action: .removeText(annotation))
                        target.needsDisplay = true
                    }
                }
            }
        case .removeText(let annotation):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    target.textAnnotations.append(annotation)
                    target.registerUndo(action: .addText(annotation))
                    target.needsDisplay = true
                }
            }
        case .moveText(let index, let oldPosition, let newPosition):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    target.textAnnotations[index].position = oldPosition
                    target.registerUndo(action: .moveText(index, newPosition, oldPosition))
                    target.needsDisplay = true
                }
            }
        case .addCounter(let counter):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
                    if !target.counterAnnotations.isEmpty {
                        target.counterAnnotations.removeLast()
                        target.nextCounterNumber = max(1, target.nextCounterNumber - 1)
                        target.registerUndo(action: .removeCounter(counter))
                        target.needsDisplay = true
                    }
                }
            }
        case .removeCounter(let counter):
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
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
            undoManager?.registerUndo(withTarget: self) { target in
                Task { @MainActor in
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
        let sideLength: CGFloat = 25.0  // Length of each side of the equilateral triangle

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
}
