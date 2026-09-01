import Cocoa
import XCTest

@testable import Annotate

@MainActor
final class QuickPickerViewTests: XCTestCase, Sendable {
    func testLaddersMatchPickerContract() {
        XCTAssertEqual(QuickPickerView.widthOptions, [1, 2, 3, 5, 8, 12, 16, 24])
        XCTAssertEqual(QuickPickerView.fontSizeOptions, [14, 18, 24, 32, 44, 60, 80, 110])
        XCTAssertEqual(QuickPickerView.counterSizeOptions, [12, 19, 26, 33, 39, 46, 53, 60])
        XCTAssertEqual(QuickPickerView.counterSizeOptions.first, counterFontSizeRange.lowerBound)
        XCTAssertEqual(QuickPickerView.counterSizeOptions.last, counterFontSizeRange.upperBound)
    }

    func testNearestAndSteppedValuesSnapBeforeMovingAndClampAtEnds() {
        XCTAssertEqual(
            QuickPickerView.steppedValue(
                in: QuickPickerView.widthOptions, current: 4.7, direction: 1),
            8)
        XCTAssertEqual(
            QuickPickerView.steppedValue(
                in: QuickPickerView.widthOptions, current: 4.7, direction: -1),
            3)
        XCTAssertEqual(
            QuickPickerView.steppedValue(
                in: QuickPickerView.widthOptions, current: 1, direction: -1),
            1)
        XCTAssertEqual(
            QuickPickerView.steppedValue(
                in: QuickPickerView.widthOptions, current: 24, direction: 1),
            24)
    }

    func testSteppedValueDoesNotInvertOutsideLadder() {
        XCTAssertEqual(
            QuickPickerView.steppedValue(
                in: QuickPickerView.widthOptions, current: 0.5, direction: -1),
            0.5)
        XCTAssertEqual(
            QuickPickerView.steppedValue(
                in: QuickPickerView.fontSizeOptions, current: 12, direction: -1),
            12)
        XCTAssertEqual(
            QuickPickerView.steppedValue(
                in: QuickPickerView.widthOptions, current: 100, direction: 1),
            100)
        XCTAssertEqual(
            QuickPickerView.steppedValue(
                in: QuickPickerView.fontSizeOptions, current: 200, direction: 1),
            200)
    }

    func testCurrentValuesSelectNearestCellsWithoutMutatingThem() {
        let widthPicker = makePicker(mode: .width, currentWidth: 4.7)
        XCTAssertEqual(widthPicker.selectedIndex, 3)
        XCTAssertEqual(widthPicker.selectedWidth, 5)

        let fontPicker = makePicker(mode: .fontSize, currentFontSize: 59)
        XCTAssertEqual(fontPicker.selectedFontSize, 60)

        let counterPicker = makePicker(mode: .counterSize, currentCounterSize: 31)
        XCTAssertEqual(counterPicker.selectedCounterSize, 33)
    }

    func testColorModeExposesAllNineDigitAddressableCells() throws {
        let picker = makePicker(mode: .color, currentColor: .black)
        XCTAssertEqual(picker.optionCount, 9)
        XCTAssertEqual(picker.selectedIndex, 8)
        XCTAssertTrue(try XCTUnwrap(picker.selectedColor).isClose(to: .black))

        picker.select(index: 0)
        XCTAssertTrue(try XCTUnwrap(picker.selectedColor).isClose(to: .systemRed))
    }

    func testSizePreviewUsesActiveToolLaydownAlpha() {
        let highlighterPicker = makePicker(mode: .width, previewTool: .highlighter)
        let penPicker = makePicker(mode: .width, previewTool: .pen)

        XCTAssertEqual(highlighterPicker.previewLaydownAlpha, ToolType.highlighter.laydownAlpha)
        XCTAssertEqual(penPicker.previewLaydownAlpha, ToolType.pen.laydownAlpha)
    }

    func testPlacementIsAboveCursorAndFlipsBelowNearTopEdge() {
        let bounds = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let above = QuickPickerView.pickerFrame(
            itemCount: 8, anchor: NSPoint(x: 500, y: 300), within: bounds)
        XCTAssertGreaterThan(above.minY, 300)

        let below = QuickPickerView.pickerFrame(
            itemCount: 8, anchor: NSPoint(x: 500, y: 780), within: bounds)
        XCTAssertLessThan(below.maxY, 780)
    }

    func testPlacementClampsToHorizontalScreenInsets() {
        let bounds = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let left = QuickPickerView.pickerFrame(
            itemCount: 9, anchor: NSPoint(x: 0, y: 300), within: bounds)
        let right = QuickPickerView.pickerFrame(
            itemCount: 9, anchor: NSPoint(x: 1_000, y: 300), within: bounds)

        XCTAssertEqual(left.minX, 8)
        XCTAssertEqual(right.maxX, bounds.maxX - 8)
    }

    func testHitTestingSelectsOnlyCellsAndIgnoresOutsideClicks() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 800))
        let picker = makePicker(mode: .width)
        container.addSubview(picker)

        let secondCell = NSPoint(
            x: picker.frame.minX + QuickPickerView.padding + QuickPickerView.cellSize * 1.5,
            y: picker.frame.minY + QuickPickerView.padding + QuickPickerView.cellSize / 2)
        XCTAssertTrue(picker.select(at: secondCell))
        XCTAssertEqual(picker.selectedIndex, 1)
        XCTAssertFalse(picker.select(at: NSPoint(x: picker.frame.minX - 1, y: picker.frame.midY)))
        XCTAssertEqual(picker.selectedIndex, 1)
    }

    func testDigitsUseVibrantSemanticLabelColorsInsteadOfFixedDarkCaptions() {
        XCTAssertEqual(QuickPickerView.digitFont.pointSize, 10)
        XCTAssertEqual(QuickPickerView.digitFontSize, 10)
        XCTAssertEqual(QuickPickerView.digitFontWeight, .medium)
        XCTAssertTrue(QuickPickerDigitView().allowsVibrancy)
    }

    func testEveryPickerModeAssignsOneBasedDigitCaptions() {
        let modes: [QuickPickerView.Mode] = [.color, .width, .fontSize, .counterSize]
        for mode in modes {
            let picker = makePicker(mode: mode)
            let cells = allSubviews(of: picker).compactMap { $0 as? QuickPickerCellView }
            XCTAssertEqual(cells.count, picker.optionCount, "\(mode) should draw one cell per option")
            XCTAssertEqual(
                cells.map(\.digit), Array(1...picker.optionCount),
                "\(mode) should label cells with digit shortcuts")
        }
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }

    private func makePicker(
        mode: QuickPickerView.Mode,
        currentColor: NSColor = .systemRed,
        currentWidth: CGFloat = 3,
        currentFontSize: CGFloat = defaultTextAnnotationFontSize,
        currentCounterSize: CGFloat = defaultCounterFontSize,
        previewTool: ToolType = .pen
    ) -> QuickPickerView {
        QuickPickerView(
            mode: mode,
            anchor: NSPoint(x: 500, y: 300),
            within: NSRect(x: 0, y: 0, width: 1_000, height: 800),
            currentColor: currentColor,
            currentWidth: currentWidth,
            currentFontSize: currentFontSize,
            currentCounterSize: currentCounterSize,
            previewTool: previewTool)
    }
}
