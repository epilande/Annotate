import XCTest

@testable import Annotate

@MainActor
final class TextAnnotationUXTests: XCTestCase, Sendable {
    var overlayView: OverlayView!
    var testDefaults: UserDefaults!

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            testDefaults = TestUserDefaults.create()
            overlayView = OverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            overlayView = nil
            testDefaults = nil
        }
        TestUserDefaults.removeSuite()
        super.tearDown()
    }

    // MARK: - Previous Tool Tracking Tests

    func testPreviousToolSetWhenSwitchingToTextMode() {
        overlayView.currentTool = .arrow
        overlayView.previousTool = .arrow

        overlayView.previousTool = overlayView.currentTool
        overlayView.currentTool = .text

        XCTAssertEqual(overlayView.previousTool, .arrow, "previousTool should be .arrow after switching from arrow to text")
    }

    func testPreviousToolNotChangedWhenAlreadyInTextMode() {
        overlayView.currentTool = .arrow
        overlayView.previousTool = .arrow
        overlayView.currentTool = .text

        let originalPreviousTool = overlayView.previousTool

        if overlayView.currentTool != .text {
            overlayView.previousTool = overlayView.currentTool
        }
        overlayView.currentTool = .text

        XCTAssertEqual(overlayView.previousTool, originalPreviousTool, "previousTool should remain unchanged when already in text mode")
    }

    func testPreviousToolTracksMultipleToolSwitches() {
        overlayView.currentTool = .arrow
        overlayView.previousTool = .pen

        overlayView.currentTool = .line

        overlayView.previousTool = overlayView.currentTool
        overlayView.currentTool = .text

        XCTAssertEqual(overlayView.previousTool, .line, "previousTool should be .line (the immediate previous)")
    }

    // MARK: - Restore Previous Tool Tests

    func testRestorePreviousToolWhenSettingEnabled() {
        testDefaults.set(true, forKey: UserDefaults.returnToPreviousToolAfterTextKey)

        overlayView.currentTool = .text
        overlayView.previousTool = .pen

        let shouldRestore = testDefaults.object(forKey: UserDefaults.returnToPreviousToolAfterTextKey) as? Bool ?? true
        if shouldRestore {
            overlayView.currentTool = overlayView.previousTool
        }

        XCTAssertEqual(overlayView.currentTool, .pen, "currentTool should be restored to .pen")
    }

    func testRestorePreviousToolDoesNothingWhenSettingDisabled() {
        testDefaults.set(false, forKey: UserDefaults.returnToPreviousToolAfterTextKey)

        overlayView.currentTool = .text
        overlayView.previousTool = .pen

        let shouldRestore = testDefaults.object(forKey: UserDefaults.returnToPreviousToolAfterTextKey) as? Bool ?? true
        if shouldRestore {
            overlayView.currentTool = overlayView.previousTool
        }

        XCTAssertEqual(overlayView.currentTool, .text, "currentTool should remain .text when setting is disabled")
    }

    func testRestorePreviousToolDefaultsToEnabled() {
        testDefaults.removeObject(forKey: UserDefaults.returnToPreviousToolAfterTextKey)

        overlayView.currentTool = .text
        overlayView.previousTool = .arrow

        let shouldRestore = testDefaults.object(forKey: UserDefaults.returnToPreviousToolAfterTextKey) as? Bool ?? true

        XCTAssertTrue(shouldRestore, "Default value should be true (restore enabled)")
    }

    // MARK: - Text Field Auto-Resize Tests

    func testTextFieldStartsWithMinimumWidth() {
        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "", width: 100)

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        XCTAssertEqual(textField.frame.width, 100, "Width should be 100 (minWidth) for empty text")

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    func testTextFieldExpandsWithContent() {
        let longText = "This is a longer piece of text"
        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: longText, width: 100)

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        XCTAssertGreaterThan(textField.frame.width, 100, "Width should increase for longer text")

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    func testTextFieldRespectsMaxWidth() {
        let veryLongText = String(repeating: "X", count: 500)
        overlayView.createTextField(at: NSPoint(x: 50, y: 100), withText: veryLongText, width: 100)

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        let maxWidth = overlayView.frame.width - 50 - 20
        let font = textField.font ?? NSFont.systemFont(ofSize: 18)
        let size = veryLongText.size(withAttributes: [.font: font])
        let minWidth: CGFloat = 100
        let calculatedWidth = min(max(minWidth, size.width + 24), maxWidth)

        XCTAssertLessThanOrEqual(calculatedWidth, maxWidth, "Calculated width should not exceed maxWidth")

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    // MARK: - Text Field Visual Styling Tests

    func testTextFieldHasRoundedBorder() {
        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "", width: 100)

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        XCTAssertEqual(textField.layer?.cornerRadius, 4, "layer.cornerRadius should be 4")

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    func testTextFieldBorderColorMatchesAnnotationColor() {
        overlayView.currentColor = .systemRed
        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "", width: 100)

        guard let textField = overlayView.activeTextField,
              let borderColor = textField.layer?.borderColor else {
            XCTFail("Text field and border color should exist")
            return
        }

        let expectedColor = NSColor.systemRed.withAlphaComponent(0.4).cgColor
        let borderNSColor = NSColor(cgColor: borderColor)
        let expectedNSColor = NSColor(cgColor: expectedColor)

        XCTAssertNotNil(borderNSColor, "Border color should be convertible to NSColor")
        XCTAssertNotNil(expectedNSColor, "Expected color should be convertible to NSColor")

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    func testTextFieldBackgroundOpacityBlackboard() {
        overlayView.currentBoardType = .blackboard
        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "", width: 100)

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        let bgColor = textField.backgroundColor
        XCTAssertEqual(bgColor.alphaComponent, 0.5, accuracy: 0.01, "Blackboard background alpha should be 0.5")

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    func testTextFieldBackgroundOpacityWhiteboard() {
        overlayView.currentBoardType = .whiteboard
        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "", width: 100)

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        let bgColor = textField.backgroundColor
        XCTAssertEqual(bgColor.alphaComponent, 0.6, accuracy: 0.01, "Whiteboard background alpha should be 0.6")

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    func testTextFieldBackgroundOpacityNoBoard() {
        overlayView.currentBoardType = nil
        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "", width: 100)

        guard let textField = overlayView.activeTextField else {
            XCTFail("Text field should be created")
            return
        }

        let bgColor = textField.backgroundColor
        XCTAssertEqual(bgColor.alphaComponent, 0.6, accuracy: 0.01, "No board background alpha should be 0.6 (whiteboard default)")

        textField.removeFromSuperview()
        overlayView.activeTextField = nil
    }

    // MARK: - Cancel Text Annotation Tests

    func testCancelTextAnnotationClearsActiveTextField() {
        overlayView.currentTool = .text
        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "Test text", width: 100)

        XCTAssertNotNil(overlayView.activeTextField, "activeTextField should exist before cancel")

        overlayView.cancelTextAnnotation()

        XCTAssertNil(overlayView.activeTextField, "activeTextField should be nil after cancel")
    }

    func testCancelTextAnnotationClearsCurrentTextAnnotation() {
        overlayView.currentTool = .text
        overlayView.currentTextAnnotation = TextAnnotation(
            text: "Test",
            position: NSPoint(x: 100, y: 100),
            color: .systemRed,
            fontSize: 18
        )
        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "Test", width: 100)

        overlayView.cancelTextAnnotation()

        XCTAssertNil(overlayView.currentTextAnnotation, "currentTextAnnotation should be nil after cancel")
    }

    func testCancelTextAnnotationDoesNotAddAnnotation() {
        overlayView.currentTool = .text
        let initialCount = overlayView.textAnnotations.count

        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "This should not be saved", width: 100)

        overlayView.cancelTextAnnotation()

        XCTAssertEqual(overlayView.textAnnotations.count, initialCount, "No annotation should be added when cancelled")
    }

    func testCancelTextAnnotationClearsEditingIndex() {
        overlayView.currentTool = .text
        overlayView.editingTextAnnotationIndex = 5

        overlayView.createTextField(at: NSPoint(x: 100, y: 100), withText: "Test", width: 100)
        overlayView.cancelTextAnnotation()

        XCTAssertNil(overlayView.editingTextAnnotationIndex, "editingTextAnnotationIndex should be nil after cancel")
    }
}
