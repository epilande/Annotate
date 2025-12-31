import Cocoa

class OverlayWindow: NSPanel {
    var overlayView: OverlayView!
    var boardView: BoardView!

    var anchorPoint: NSPoint = .zero
    private var isOptionCurrentlyPressed = false
    private var wasOptionPressedOnMouseDown = false
    private var isCenterModeActive = false

    // Shift key state tracking for straight line constraint
    private var isShiftCurrentlyPressed = false
    private var wasShiftPressedOnMouseDown = false
    private var isShiftConstraintActive = false

    var fadeTimer: Timer?
    let fadeInterval: TimeInterval = 1.0 / 60.0
    
    // Track the current feedback view to remove it when a new one appears
    private var currentFeedbackView: NSView?
    private var feedbackRemovalTask: DispatchWorkItem?
    
    // Create undo manager for this window
    private let _undoManager = UndoManager()
    
    override var undoManager: UndoManager? {
        return _undoManager
    }

    var currentColor: NSColor {
        get { overlayView.currentColor }
        set {
            overlayView.currentColor = newValue
            overlayView.needsDisplay = true
        }
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        let windowRect = NSRect(
            x: contentRect.origin.x,
            y: contentRect.origin.y,
            width: contentRect.width,
            height: contentRect.height
        )

        super.init(
            contentRect: windowRect,
            styleMask: style.union([.nonactivatingPanel]),
            backing: backingStoreType,
            defer: flag)

        configureWindowLevel()
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.setFrame(windowRect, display: true)

        let containerView = NSView(frame: NSRect(origin: .zero, size: windowRect.size))

        let boardFrame = NSRect(
            x: 0,
            y: 0,
            width: windowRect.width,
            height: windowRect.height
        )
        boardView = BoardView(frame: boardFrame)
        boardView.isHidden = !BoardManager.shared.isEnabled
        containerView.addSubview(boardView)

        overlayView = OverlayView(frame: containerView.bounds)
        overlayView.wantsLayer = true
        overlayView.layer?.opacity = 0.9
        containerView.addSubview(overlayView)

        self.contentView = containerView
    }

    private func configureWindowLevel() {
        let levels = [
            CGWindowLevelForKey(.mainMenuWindow),
            CGWindowLevelForKey(.statusWindow),
            CGWindowLevelForKey(.popUpMenuWindow),
            CGWindowLevelForKey(.assistiveTechHighWindow),
            CGWindowLevelForKey(.screenSaverWindow)
        ]

        let maxLevel = levels.map { Int($0) + 1 }.max() ?? Int(CGWindowLevelForKey(.statusWindow)) + 1
        level = NSWindow.Level(rawValue: maxLevel)
    }

    func startFadeLoop() {
        guard fadeTimer == nil else { return }
        fadeTimer = Timer.scheduledTimer(
            timeInterval: fadeInterval,
            target: self,
            selector: #selector(updateFade),
            userInfo: nil,
            repeats: true
        )
    }

    func stopFadeLoop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    @objc func updateFade() {
        overlayView.needsDisplay = true

        // Stop the loop if nothing is actively fading
        if !overlayView.isAnythingFading() {
            stopFadeLoop()
        }
    }

    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }

    func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Update cursor highlight for local events (global monitors don't capture our own app's events)
        let cursorManager = CursorHighlightManager.shared
        if cursorManager.isActive {
            cursorManager.cursorPosition = NSEvent.mouseLocation
            cursorManager.isMouseDown = true
            cursorManager.mouseDownTime = CACurrentMediaTime()
            // Only notify on mouseDown to start animation loop
            NotificationCenter.default.post(name: .cursorHighlightNeedsUpdate, object: nil)
        }

        let startPoint = event.locationInWindow
        anchorPoint = startPoint
        overlayView.lastMousePosition = startPoint  // Track mouse position for paste
        wasOptionPressedOnMouseDown = event.modifierFlags.contains(.option)
        isCenterModeActive = wasOptionPressedOnMouseDown
        wasShiftPressedOnMouseDown = event.modifierFlags.contains(.shift)
        isShiftConstraintActive = wasShiftPressedOnMouseDown
        let clickCount = event.clickCount
        let shiftPressed = event.modifierFlags.contains(.shift)

        if let activeTextField = overlayView.activeTextField {
            overlayView.finalizeTextAnnotation(activeTextField)
        }
        
        // Handle selection mode
        if overlayView.currentTool == .select {
            // First check if we clicked inside the bounding box of already selected objects
            if !overlayView.selectedObjects.isEmpty && overlayView.isPointInSelectionBoundingBox(startPoint) {
                // Clicked inside the selection bounding box
                if shiftPressed {
                    // Shift+click inside bounding box - find which specific object to toggle
                    let foundObject = overlayView.findObjectAt(point: startPoint)
                    if foundObject != .none {
                        if overlayView.selectedObjects.contains(foundObject) {
                            overlayView.selectedObjects.remove(foundObject)
                        } else {
                            overlayView.selectedObjects.insert(foundObject)
                        }
                    }
                    overlayView.selectionDragOffset = nil
                } else {
                    // Regular click inside bounding box - prepare to drag all selected objects
                    overlayView.selectionDragOffset = startPoint
                    
                    // Store original positions for undo
                    overlayView.selectionOriginalData.removeAll()
                    for obj in overlayView.selectedObjects {
                        if let pos = overlayView.getObjectPosition(obj) {
                            overlayView.selectionOriginalData[obj] = pos
                        }
                    }
                }
                
                overlayView.needsDisplay = true
                return
            }
            
            // Not inside bounding box, do normal hit test to find objects
            let foundObject = overlayView.findObjectAt(point: startPoint)
            
            if foundObject != .none {
                // Shift+Click: Toggle object in selection
                if shiftPressed {
                    if overlayView.selectedObjects.contains(foundObject) {
                        overlayView.selectedObjects.remove(foundObject)
                    } else {
                        overlayView.selectedObjects.insert(foundObject)
                    }
                    // Don't set drag offset for shift+click (we're just toggling selection)
                    overlayView.selectionDragOffset = nil
                } else {
                    // Regular click
                    if !overlayView.selectedObjects.contains(foundObject) {
                        // Object not in selection, select only this object
                        overlayView.selectedObjects = [foundObject]
                    }
                    // else: object is already in selection, keep current selection and prepare to drag all
                    
                    // Always set drag offset for regular click (for dragging)
                    overlayView.selectionDragOffset = startPoint
                }
                
                // Store original positions for undo
                overlayView.selectionOriginalData.removeAll()
                for obj in overlayView.selectedObjects {
                    if let pos = overlayView.getObjectPosition(obj) {
                        overlayView.selectionOriginalData[obj] = pos
                    }
                }
                
                overlayView.needsDisplay = true
                return
            } else {
                // Clicked on empty space
                if !shiftPressed {
                    // Clear selection if not holding shift
                    overlayView.selectedObjects.removeAll()
                }
                // Start rectangle selection
                overlayView.isDrawingSelectionRect = true
                overlayView.selectionRectStart = startPoint
                overlayView.selectionRectEnd = startPoint
                overlayView.selectionDragOffset = nil  // Not dragging
                overlayView.needsDisplay = true
                return
            }
        }

        if overlayView.currentTool == .counter {
            let counterAnnotation = CounterAnnotation(
                number: overlayView.nextCounterNumber,
                position: startPoint,
                color: currentColor,
                creationTime: CACurrentMediaTime()
            )

            overlayView.registerUndo(action: .addCounter(counterAnnotation))
            overlayView.counterAnnotations.append(counterAnnotation)
            overlayView.nextCounterNumber += 1
            overlayView.needsDisplay = true

            if overlayView.fadeMode {
                startFadeLoop()
            }
            return
        }

        if overlayView.currentTool == .text {
            for (index, annotation) in overlayView.textAnnotations.enumerated() {
                let textRect = getTextRect(for: annotation)
                if textRect.contains(startPoint) {
                    if clickCount == 1 {
                        // Single click - prepare for dragging
                        overlayView.draggedTextAnnotationIndex = index
                        overlayView.dragOffset = NSPoint(
                            x: startPoint.x - annotation.position.x,
                            y: startPoint.y - annotation.position.y
                        )
                        overlayView.originalTextPosition = annotation.position
                    } else if clickCount == 2 {
                        // Double click - edit text
                        overlayView.editingTextAnnotationIndex = index
                        let existingAnnotation = overlayView.textAnnotations[index]

                        let attributes: [NSAttributedString.Key: Any] = [
                            .font: NSFont.systemFont(ofSize: 18)
                        ]
                        let size = existingAnnotation.text.size(withAttributes: attributes)

                        overlayView.createTextField(
                            at: existingAnnotation.position,
                            withText: existingAnnotation.text,
                            width: max(300, size.width + 20)
                        )
                    }
                    return
                }
            }

            // If we didn't click on existing text, create new one
            overlayView.currentTextAnnotation = TextAnnotation(
                text: "",
                position: startPoint,
                color: currentColor,
                fontSize: 18
            )
            overlayView.createTextField(at: startPoint)
        }

        switch overlayView.currentTool {
        case .pen:
            let t = CACurrentMediaTime()
            overlayView.currentPath = DrawingPath(
                points: [TimedPoint(point: startPoint, timestamp: t)],
                color: currentColor,
                lineWidth: overlayView.currentLineWidth)
        case .arrow:
            overlayView.currentArrow = Arrow(
                startPoint: startPoint, endPoint: startPoint, color: currentColor, lineWidth: overlayView.currentLineWidth, creationTime: nil)
        case .line:
            overlayView.currentLine = Line(
                startPoint: startPoint, endPoint: startPoint, color: currentColor, lineWidth: overlayView.currentLineWidth, creationTime: nil)
        case .highlighter:
            let t = CACurrentMediaTime()
            overlayView.currentHighlight = DrawingPath(
                points: [TimedPoint(point: startPoint, timestamp: t)],
                color: currentColor.withAlphaComponent(0.3),
                lineWidth: overlayView.currentLineWidth)
        case .rectangle:
            overlayView.currentRectangle = Rectangle(
                startPoint: startPoint, endPoint: startPoint, color: overlayView.currentColor, lineWidth: overlayView.currentLineWidth, creationTime: nil)
        case .circle:
            overlayView.currentCircle = Circle(
                startPoint: startPoint, endPoint: startPoint, color: overlayView.currentColor, lineWidth: overlayView.currentLineWidth, creationTime: nil)
        case .text:
            break
        case .counter:
            break
        case .select:
            break
        case .eraser:
            overlayView.eraseAtPoint(startPoint)
        }
        overlayView.needsDisplay = true
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

    override func mouseDragged(with event: NSEvent) {
        // Update cursor highlight position during drag (animation loop handles rendering)
        let cursorManager = CursorHighlightManager.shared
        if cursorManager.isActive && cursorManager.isMouseDown {
            cursorManager.cursorPosition = NSEvent.mouseLocation
            // No notification needed - animation loop already running from mouseDown
        }

        overlayView.needsDisplay = true
        let currentPoint = event.locationInWindow
        overlayView.lastMousePosition = currentPoint  // Track mouse position for paste
        
        // Handle rectangle selection drawing
        if overlayView.currentTool == .select && overlayView.isDrawingSelectionRect {
            overlayView.selectionRectEnd = currentPoint
            overlayView.needsDisplay = true
            return
        }
        
        // Handle selection dragging
        if overlayView.currentTool == .select && !overlayView.selectedObjects.isEmpty {
            // Get or set drag start point
            let dragStart = overlayView.selectionDragOffset ?? currentPoint
            if overlayView.selectionDragOffset == nil {
                overlayView.selectionDragOffset = currentPoint
                return  // Wait for next drag event to actually move
            }
            
            let delta = NSPoint(
                x: currentPoint.x - dragStart.x,
                y: currentPoint.y - dragStart.y
            )
            
            overlayView.moveSelectedObjects(by: delta)
            overlayView.selectionDragOffset = currentPoint
            overlayView.needsDisplay = true
            return
        }

        if let draggedIndex = overlayView.draggedTextAnnotationIndex,
            let dragOffset = overlayView.dragOffset
        {
            // Update the position of the dragged text annotation
            let newPosition = NSPoint(
                x: currentPoint.x - dragOffset.x,
                y: currentPoint.y - dragOffset.y
            )
            overlayView.textAnnotations[draggedIndex].position = newPosition
            overlayView.needsDisplay = true
            return
        }

        switch overlayView.currentTool {
        case .pen:
            let t = CACurrentMediaTime()
            if isShiftConstraintActive {
                updatePathWithShiftConstraint(
                    path: &overlayView.currentPath,
                    to: currentPoint,
                    timestamp: t
                )
            } else {
                overlayView.currentPath?.points.append(TimedPoint(point: currentPoint, timestamp: t))
            }
        case .arrow:
            overlayView.currentArrow?.endPoint = isShiftConstraintActive
                ? snapToStraightLine(from: anchorPoint, to: currentPoint)
                : currentPoint
        case .line:
            overlayView.currentLine?.endPoint = isShiftConstraintActive
                ? snapToStraightLine(from: anchorPoint, to: currentPoint)
                : currentPoint
        case .highlighter:
            let t = CACurrentMediaTime()
            if isShiftConstraintActive {
                updatePathWithShiftConstraint(
                    path: &overlayView.currentHighlight,
                    to: currentPoint,
                    timestamp: t
                )
            } else {
                overlayView.currentHighlight?.points.append(
                    TimedPoint(point: currentPoint, timestamp: t))
            }
        case .rectangle:
            if isCenterModeActive {
                let dx = currentPoint.x - anchorPoint.x
                let dy = currentPoint.y - anchorPoint.y
                let newStart = NSPoint(x: anchorPoint.x - dx, y: anchorPoint.y - dy)
                let newEnd = NSPoint(x: anchorPoint.x + dx, y: anchorPoint.y + dy)
                overlayView.currentRectangle?.startPoint = newStart
                overlayView.currentRectangle?.endPoint = newEnd
            } else {
                overlayView.currentRectangle?.endPoint = currentPoint
            }
        case .circle:
            if isCenterModeActive {
                let dx = currentPoint.x - anchorPoint.x
                let dy = currentPoint.y - anchorPoint.y
                let newStart = NSPoint(x: anchorPoint.x - dx, y: anchorPoint.y - dy)
                let newEnd = NSPoint(x: anchorPoint.x + dx, y: anchorPoint.y + dy)
                overlayView.currentCircle?.startPoint = newStart
                overlayView.currentCircle?.endPoint = newEnd
            } else {
                overlayView.currentCircle?.endPoint = currentPoint
            }
        case .text:
            break
        case .counter:
            break
        case .select:
            break
        case .eraser:
            overlayView.eraseAtPoint(currentPoint)
        }
        overlayView.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let cursorManager = CursorHighlightManager.shared
        if cursorManager.isActive {
            cursorManager.startReleaseAnimation()
            cursorManager.isMouseDown = false
            NotificationCenter.default.post(name: .cursorHighlightNeedsUpdate, object: nil)
        }

        overlayView.needsDisplay = true

        // Handle rectangle selection end
        if overlayView.currentTool == .select && overlayView.isDrawingSelectionRect {
            if let start = overlayView.selectionRectStart, let end = overlayView.selectionRectEnd {
                let rect = NSRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                
                // Find objects in rectangle
                let objectsInRect = overlayView.findObjectsInRect(rect)
                
                // Check if shift is still pressed
                let shiftPressed = event.modifierFlags.contains(.shift)
                if shiftPressed {
                    // Add to existing selection
                    overlayView.selectedObjects.formUnion(objectsInRect)
                } else {
                    // Replace selection
                    overlayView.selectedObjects = objectsInRect
                }
            }
            
            overlayView.isDrawingSelectionRect = false
            overlayView.selectionRectStart = nil
            overlayView.selectionRectEnd = nil
            overlayView.needsDisplay = true
            return
        }
        
        // Handle selection drag end
        if overlayView.currentTool == .select && !overlayView.selectedObjects.isEmpty {
            // Register undo for all moved objects
            for obj in overlayView.selectedObjects {
                if let originalData = overlayView.selectionOriginalData[obj] {
                    let newData = overlayView.getObjectPosition(obj)
                    if let newPos = newData {
                        overlayView.registerMoveUndo(
                            object: obj,
                            from: originalData,
                            to: newPos
                        )
                    }
                }
            }
            overlayView.selectionDragOffset = nil
            overlayView.selectionOriginalData.removeAll()
            return
        }

        if let draggedIndex = overlayView.draggedTextAnnotationIndex {
            let oldPosition =
                overlayView.originalTextPosition
                ?? overlayView.textAnnotations[draggedIndex].position
            let newPosition = overlayView.textAnnotations[draggedIndex].position
            if newPosition != oldPosition {
                overlayView.registerUndo(action: .moveText(draggedIndex, oldPosition, newPosition))
            }
            overlayView.draggedTextAnnotationIndex = nil
            overlayView.originalTextPosition = nil
            overlayView.dragOffset = nil
        }

        switch overlayView.currentTool {
        case .pen:
            if var currentPath = overlayView.currentPath {
                let finalTime = CACurrentMediaTime()
                // Find the oldest point’s timestamp
                guard let minTimestamp = currentPath.points.map({ $0.timestamp }).min() else {
                    return
                }
                var updatedPoints = currentPath.points
                // Shift each point so that the oldest is effectively 0 at mouseUp
                let offset = finalTime - minTimestamp
                for i in 0..<updatedPoints.count {
                    updatedPoints[i].timestamp += offset
                }
                currentPath.points = updatedPoints
                overlayView.registerUndo(action: .addPath(currentPath))
                overlayView.paths.append(currentPath)
                overlayView.currentPath = nil
            }
        case .arrow:
            if var currentArrow = overlayView.currentArrow {
                currentArrow.creationTime = CACurrentMediaTime()
                overlayView.registerUndo(action: .addArrow(currentArrow))
                overlayView.arrows.append(currentArrow)
                overlayView.currentArrow = nil
            }
        case .line:
            if var currentLine = overlayView.currentLine {
                currentLine.creationTime = CACurrentMediaTime()
                overlayView.registerUndo(action: .addLine(currentLine))
                overlayView.lines.append(currentLine)
                overlayView.currentLine = nil
            }
        case .highlighter:
            if var currentHighlight = overlayView.currentHighlight {
                let finalTime = CACurrentMediaTime()
                // Find the oldest point’s timestamp
                guard let minTimestamp = currentHighlight.points.map({ $0.timestamp }).min() else {
                    return
                }
                var updatedPoints = currentHighlight.points
                // Shift each point so that the oldest is effectively 0 at mouseUp
                let offset = finalTime - minTimestamp
                for i in 0..<updatedPoints.count {
                    updatedPoints[i].timestamp += offset
                }
                currentHighlight.points = updatedPoints
                overlayView.registerUndo(action: .addHighlight(currentHighlight))
                overlayView.highlightPaths.append(currentHighlight)
                overlayView.currentHighlight = nil
            }
        case .rectangle:
            if var currentRectangle = overlayView.currentRectangle {
                currentRectangle.creationTime = CACurrentMediaTime()
                overlayView.registerUndo(action: .addRectangle(currentRectangle))
                overlayView.rectangles.append(currentRectangle)
                overlayView.currentRectangle = nil
            }
        case .circle:
            if var currentCircle = overlayView.currentCircle {
                currentCircle.creationTime = CACurrentMediaTime()
                overlayView.registerUndo(action: .addCircle(currentCircle))
                overlayView.circles.append(currentCircle)
                overlayView.currentCircle = nil
            }
        case .text:
            break
        case .counter:
            break
        case .select:
            break
        case .eraser:
            break
        }
        overlayView.needsDisplay = true
        wasOptionPressedOnMouseDown = false
        isCenterModeActive = false
        wasShiftPressedOnMouseDown = false
        isShiftConstraintActive = false

        if overlayView.fadeMode {
            startFadeLoop()
        }
    }

    override func keyDown(with event: NSEvent) {
        let cmdPressed = event.modifierFlags.contains(.command)
        let key = event.characters?.lowercased() ?? ""
        
        // Handle single-key shortcuts if no modifiers are pressed
        if !cmdPressed
            && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        {
            switch key {
            case ShortcutManager.shared.getShortcut(for: .pen):
                AppDelegate.shared?.enablePenMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .arrow):
                AppDelegate.shared?.enableArrowMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .line):
                AppDelegate.shared?.enableLineMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .highlighter):
                AppDelegate.shared?.enableHighlighterMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .rectangle):
                AppDelegate.shared?.enableRectangleMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .circle):
                AppDelegate.shared?.enableCircleMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .counter):
                AppDelegate.shared?.enableCounterMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .text):
                AppDelegate.shared?.enableTextMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .select):
                AppDelegate.shared?.enableSelectMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .eraser):
                AppDelegate.shared?.enableEraserMode(NSMenuItem())
                return
            case ShortcutManager.shared.getShortcut(for: .colorPicker):
                AppDelegate.shared?.showColorPicker(nil)
                return
            case ShortcutManager.shared.getShortcut(for: .lineWidthPicker):
                AppDelegate.shared?.showLineWidthPicker(nil)
                return
            case ShortcutManager.shared.getShortcut(for: .toggleBoard):
                AppDelegate.shared?.toggleBoardVisibility(nil)
                return
            default:
                break
            }
        }

        switch event.keyCode {
        case 53:  // ESC key
            if event.modifierFlags.contains(.shift) {
                AppDelegate.shared?.closeOverlayAndEnableAlwaysOn()
            } else {
                AppDelegate.shared?.toggleOverlay()
            }
        case 51:  // Delete/Backspace key
            if event.modifierFlags.contains(.option) {
                overlayView.clearAll()
            } else {
                overlayView.deleteLastItem()
            }
        case 117:  // Forward Delete key (fn+delete)
            if event.modifierFlags.contains(.option) {
                overlayView.clearAll()
            } else {
                overlayView.deleteLastItem()
            }
        case 49:  // Spacebar - toggle drawing mode
            AppDelegate.shared?.toggleFadeMode(NSMenuItem())
        case 13:  // 'w' key
            if cmdPressed { AppDelegate.shared?.closeOverlay() }
        case 6:  // 'z' key
            if cmdPressed {
                if event.modifierFlags.contains(.shift) {
                    overlayView.redo()
                } else {
                    overlayView.undo()
                }
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        let optionPressed = event.modifierFlags.contains(.option)
        let shiftPressed = event.modifierFlags.contains(.shift)

        // Handle Option key for center mode (rectangles and circles)
        if !wasOptionPressedOnMouseDown {
            if !isOptionCurrentlyPressed && optionPressed {
                recenterAnchorForCurrentShape()
                isCenterModeActive = true
            } else if isOptionCurrentlyPressed && !optionPressed {
                isCenterModeActive = false
            }
        }

        // Handle Shift key for straight line constraint
        if !wasShiftPressedOnMouseDown {
            if !isShiftCurrentlyPressed && shiftPressed {
                // Shift pressed mid-drag - activate constraint
                isShiftConstraintActive = true
            } else if isShiftCurrentlyPressed && !shiftPressed {
                // Shift released mid-drag - deactivate constraint
                isShiftConstraintActive = false
            }
        }

        isOptionCurrentlyPressed = optionPressed
        isShiftCurrentlyPressed = shiftPressed
    }

    private func recenterAnchorForCurrentShape() {
        if let rect = overlayView.currentRectangle {
            let boundingRect = NSRect(
                x: min(rect.startPoint.x, rect.endPoint.x),
                y: min(rect.startPoint.y, rect.endPoint.y),
                width: abs(rect.endPoint.x - rect.startPoint.x),
                height: abs(rect.endPoint.y - rect.startPoint.y)
            )
            anchorPoint = NSPoint(x: boundingRect.midX, y: boundingRect.midY)
        } else if let circle = overlayView.currentCircle {
            let boundingRect = NSRect(
                x: min(circle.startPoint.x, circle.endPoint.x),
                y: min(circle.startPoint.y, circle.endPoint.y),
                width: abs(circle.endPoint.x - circle.startPoint.x),
                height: abs(circle.endPoint.y - circle.startPoint.y)
            )
            anchorPoint = NSPoint(x: boundingRect.midX, y: boundingRect.midY)
        }
    }

    /// Updates a drawing path with shift constraint, keeping only start and snapped endpoint
    /// - Parameters:
    ///   - path: The drawing path to update (pen or highlighter)
    ///   - current: The current mouse position
    ///   - timestamp: The current timestamp
    private func updatePathWithShiftConstraint(
        path: inout DrawingPath?,
        to current: NSPoint,
        timestamp: TimeInterval
    ) {
        guard var currentPath = path, !currentPath.points.isEmpty else { return }
        let startPoint = currentPath.points[0].point
        let snappedPoint = snapToStraightLine(from: startPoint, to: current)
        currentPath.points = [
            TimedPoint(point: startPoint, timestamp: currentPath.points[0].timestamp),
            TimedPoint(point: snappedPoint, timestamp: timestamp)
        ]
        path = currentPath
    }

    /// Snaps a point to the nearest 45-degree angle from a start point
    /// - Parameters:
    ///   - start: The starting point (anchor point)
    ///   - current: The current mouse position
    /// - Returns: A new point snapped to the nearest 45-degree increment
    private func snapToStraightLine(from start: NSPoint, to current: NSPoint) -> NSPoint {
        let dx = current.x - start.x
        let dy = current.y - start.y
        let distance = sqrt(dx * dx + dy * dy)

        // Handle edge case: zero distance
        guard distance > 0 else {
            return start
        }

        let angle = atan2(dy, dx)

        // Find nearest 45-degree increment (π/4 radians)
        let snapAngle = round(angle / (.pi / 4)) * (.pi / 4)

        // Calculate new endpoint maintaining distance but snapped angle
        return NSPoint(
            x: start.x + distance * cos(snapAngle),
            y: start.y + distance * sin(snapAngle)
        )
    }
    
    override func scrollWheel(with event: NSEvent) {
        // Check if Command key is pressed
        let cmdPressed = event.modifierFlags.contains(.command)
        
        if cmdPressed {
            scrollWheelForLineWidth(with: event)
        } else {
            // Default scroll behavior
            super.scrollWheel(with: event)
        }
    }
    
    // Support for mouse backward/forward buttons (typically buttons 3 and 4)
    override func otherMouseDown(with event: NSEvent) {
        // Button numbers:
        // 2 = middle mouse button
        // 3 = backward button (typically)
        // 4 = forward button (typically)
        
        switch event.buttonNumber {
        case 3:  // Backward button - Undo
            overlayView.undo()
        case 4:  // Forward button - Redo
            overlayView.redo()
        default:
            super.otherMouseDown(with: event)
        }
    }
    
    private func scrollWheelForLineWidth(with event: NSEvent) {
        // Adjust line width with Command + Scroll
        let minLineWidth: CGFloat = 0.5
        let maxLineWidth: CGFloat = 20.0
        let ratio: CGFloat = 0.25
        
        // Get scroll delta (negative means scroll up, positive means scroll down)
        let scrollDelta = event.scrollingDeltaY
        
        // Determine direction and amount
        let increment: CGFloat = scrollDelta > 0 ? ratio : -ratio
        
        // Get current line width
        let currentWidth = overlayView.currentLineWidth
        
        // Calculate new width
        var newWidth = currentWidth + increment
        
        // Round to nearest ratio increment
        newWidth = round(newWidth / ratio) * ratio
        
        // Clamp to min/max
        newWidth = max(minLineWidth, min(maxLineWidth, newWidth))
        
        // Only update if value changed
        if newWidth != currentWidth {
            // Update the line width globally
            overlayView.currentLineWidth = newWidth
            
            // Save to UserDefaults
            UserDefaults.standard.set(Double(newWidth), forKey: UserDefaults.lineWidthKey)
            
            // Apply to all overlay windows
            AppDelegate.shared?.overlayWindows.values.forEach { window in
                window.overlayView.currentLineWidth = newWidth
            }
            
            // Show visual feedback
            showLineWidthFeedback(newWidth)
        }
    }
    
    private func showLineWidthFeedback(_ width: CGFloat) {
        let text = String(format: "Line Width: %.2f px", width)
        showFeedback(text, lineColor: overlayView.currentColor, lineWidth: width)
    }
    
    func showToolFeedback(_ tool: ToolType) {
        // Check if tool feedback is hidden in settings (default: false, meaning show feedback)
        let hideToolFeedback = UserDefaults.standard.bool(forKey: UserDefaults.hideToolFeedbackKey)
        guard !hideToolFeedback else { return }

        let toolName: String
        let icon: String

        switch tool {
        case .pen:
            toolName = "Pen"
            icon = "✒️"
        case .arrow:
            toolName = "Arrow"
            icon = "➡️"
        case .line:
            toolName = "Line"
            icon = "📏"
        case .highlighter:
            toolName = "Highlighter"
            icon = "🟨"
        case .rectangle:
            toolName = "Rectangle"
            icon = "🔲"
        case .circle:
            toolName = "Circle"
            icon = "⭕"
        case .counter:
            toolName = "Counter"
            icon = "🔢"
        case .text:
            toolName = "Text"
            icon = "📝"
        case .select:
            toolName = "Select"
            icon = "👆"
        case .eraser:
            toolName = "Eraser"
            icon = "🧹"
        }

        let currentWidth = overlayView.currentLineWidth

        switch tool {
        case .pen, .arrow, .line, .highlighter, .rectangle, .circle:
            let widthText = String(format: "%.2f px", currentWidth)
            let text = "\(icon) \(toolName) • \(widthText)"
            showFeedback(text, lineColor: overlayView.currentColor, lineWidth: currentWidth)
        case .counter, .text, .select, .eraser:
            let text = "\(icon) \(toolName)"
            showFeedback(text, lineColor: overlayView.currentColor)
        }
    }
    
    /// Shows a feedback message at the bottom center of the screen
    /// - Parameters:
    ///   - text: The message to display
    ///   - duration: How long to show the message (default: 1.5 seconds)
    ///   - fadeOutDuration: How long the fade out animation takes (default: 0.5 seconds)
    ///   - lineColor: Optional line color for preview (default: nil for no line)
    ///   - lineWidth: Optional line width for preview (default: nil for no line)
    
    private func showFeedback(
        _ text: String,
        duration: TimeInterval = 1.5,
        fadeOutDuration: TimeInterval = 0.5,
        lineColor: NSColor? = nil,
        lineWidth: CGFloat? = nil
    ) {
        removePreviousFeedback()
        
        let containerView = createFeedbackContainer(
            text: text,
            lineColor: lineColor,
            lineWidth: lineWidth
        )
        
        overlayView.addSubview(containerView)
        currentFeedbackView = containerView
        
        scheduleFeedbackRemoval(
            containerView: containerView,
            duration: duration,
            fadeOutDuration: fadeOutDuration
        )
    }
    
    private func removePreviousFeedback() {
        feedbackRemovalTask?.cancel()
        
        if let previousView = currentFeedbackView {
            previousView.removeFromSuperview()
            currentFeedbackView = nil
        }
    }
    
    private func createFeedbackContainer(
        text: String,
        lineColor: NSColor?,
        lineWidth: CGFloat?
    ) -> NSView {
        let containerWidth = calculateFeedbackContainerWidth(for: text)
        let containerHeight: CGFloat = (lineWidth != nil) ? 80 : 50
        let containerFrame = calculateFeedbackContainerFrame(
            width: containerWidth,
            height: containerHeight,
            lineWidth: lineWidth
        )
        
        let containerView = NSView(frame: containerFrame)
        configureFeedbackContainerStyle(containerView)

        let feedbackLabel = createFeedbackLabel(
            text: text,
            containerWidth: containerWidth,
            containerHeight: containerHeight
        )
        containerView.addSubview(feedbackLabel)
        
        if let lineColor = lineColor, let lineWidth = lineWidth {
            let lineView = createLinePreview(
                lineColor: lineColor,
                lineWidth: lineWidth,
                containerWidth: containerWidth
            )
            containerView.addSubview(lineView)
        }
        
        return containerView
    }
    
    private func calculateFeedbackContainerWidth(for text: String) -> CGFloat {
        let labelPadding: CGFloat = 10
        let extraMargin: CGFloat = 40
        let font = NSFont.boldSystemFont(ofSize: 24)
        let textSize = text.size(withAttributes: [.font: font])
        
        // Container width = text width + horizontal padding + margins
        let minWidth: CGFloat = 150
        let maxWidth: CGFloat = 400
        let calculatedWidth = textSize.width + (labelPadding * 2) + extraMargin
        
        return min(max(minWidth, calculatedWidth), maxWidth)
    }
    
    private func calculateFeedbackContainerFrame(
        width: CGFloat,
        height: CGFloat,
        lineWidth: CGFloat?
    ) -> NSRect {
        let bottomPadding: CGFloat = 20
        let extraLinePadding = lineWidth != nil ? max(0, lineWidth! / 2) : 0
        
        return NSRect(
            x: (frame.width - width) / 2,
            y: bottomPadding + extraLinePadding,
            width: width,
            height: height
        )
    }
    
    private func configureFeedbackContainerStyle(_ containerView: NSView) {
        containerView.wantsLayer = true

        // Respect system appearance (Dark Mode vs Light Mode)
        let isDarkMode = isDarkModeActive()
        let backgroundColor: NSColor = isDarkMode
            ? NSColor.black.withAlphaComponent(0.75)
            : NSColor.white.withAlphaComponent(0.85)

        containerView.layer?.backgroundColor = backgroundColor.cgColor
        containerView.layer?.cornerRadius = 8
    }
    
    private func createFeedbackLabel(
        text: String,
        containerWidth: CGFloat,
        containerHeight: CGFloat
    ) -> NSTextField {
        let labelPadding: CGFloat = 10
        let textVerticalPadding: CGFloat = 10

        let feedbackLabel = NSTextField(labelWithString: text)
        feedbackLabel.font = NSFont.boldSystemFont(ofSize: 24)
        feedbackLabel.backgroundColor = .clear
        feedbackLabel.isBordered = false
        feedbackLabel.isEditable = false
        feedbackLabel.isSelectable = false
        feedbackLabel.alignment = .center

        // Set text color based on system appearance
        feedbackLabel.textColor = isDarkModeActive() ? .white : .black

        let textSize = text.size(withAttributes: [.font: feedbackLabel.font!])
        feedbackLabel.frame = NSRect(
            x: labelPadding,
            y: containerHeight - textSize.height - textVerticalPadding,
            width: containerWidth - (labelPadding * 2),
            height: textSize.height
        )

        return feedbackLabel
    }
    
    private func createLinePreview(
        lineColor: NSColor,
        lineWidth: CGFloat,
        containerWidth: CGFloat
    ) -> LinePreviewView {
        let labelPadding: CGFloat = 10
        let textVerticalPadding: CGFloat = 10
        
        let lineView = LinePreviewView(frame: NSRect(
            x: labelPadding,
            y: textVerticalPadding,
            width: containerWidth - (labelPadding * 2),
            height: max(lineWidth, 10)
        ))
        lineView.lineColor = lineColor
        lineView.lineWidth = lineWidth
        
        return lineView
    }
    
    private func isDarkModeActive() -> Bool {
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func scheduleFeedbackRemoval(
        containerView: NSView,
        duration: TimeInterval,
        fadeOutDuration: TimeInterval
    ) {
        let totalDuration = duration + fadeOutDuration
        let removalTask = DispatchWorkItem { [weak self, weak containerView] in
            guard let view = containerView else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = fadeOutDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                view.animator().alphaValue = 0
            }, completionHandler: {
                view.removeFromSuperview()
                if self?.currentFeedbackView == view {
                    self?.currentFeedbackView = nil
                }
            })
        }
        
        feedbackRemovalTask = removalTask
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: removalTask)
        
        // Schedule removal in case animation doesn't complete
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.5) { [weak self, weak containerView] in
            guard let view = containerView else { return }
            if view.superview != nil {
                view.removeFromSuperview()
                if self?.currentFeedbackView == view {
                    self?.currentFeedbackView = nil
                }
            }
        }
    }
    
    // MARK: - Keyboard Commands for Copy/Paste/Cut/Duplicate
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Check for Command key combinations
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a":
            // Defer to text field when editing text
            if overlayView.activeTextField != nil {
                return super.performKeyEquivalent(with: event)
            }

            let hasAnnotations = !overlayView.arrows.isEmpty || !overlayView.lines.isEmpty ||
                                !overlayView.paths.isEmpty || !overlayView.highlightPaths.isEmpty ||
                                !overlayView.rectangles.isEmpty || !overlayView.circles.isEmpty ||
                                !overlayView.textAnnotations.isEmpty || !overlayView.counterAnnotations.isEmpty

            if hasAnnotations {
                if overlayView.currentTool != .select {
                    AppDelegate.shared?.enableSelectMode(NSMenuItem())
                }
                overlayView.selectAllObjects()
            }

            return true

        case "c":
            guard overlayView.currentTool == .select else {
                return super.performKeyEquivalent(with: event)
            }
            overlayView.copySelectedObjects()
            return true

        case "x":
            guard overlayView.currentTool == .select else {
                return super.performKeyEquivalent(with: event)
            }
            overlayView.cutSelectedObjects()
            return true

        case "v":
            guard overlayView.currentTool == .select else {
                return super.performKeyEquivalent(with: event)
            }
            overlayView.pasteObjects()
            return true

        case "d":
            guard overlayView.currentTool == .select else {
                return super.performKeyEquivalent(with: event)
            }
            overlayView.duplicateSelectedObjects()
            return true
            
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

// Helper view to draw a line preview in the feedback overlay
class LinePreviewView: NSView {
    var lineColor: NSColor = .white
    var lineWidth: CGFloat = 3.0
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let path = NSBezierPath()
        let startPoint = NSPoint(x: 0, y: bounds.midY)
        let endPoint = NSPoint(x: bounds.width, y: bounds.midY)
        
        path.move(to: startPoint)
        path.line(to: endPoint)
        
        lineColor.setStroke()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.stroke()
    }
}
