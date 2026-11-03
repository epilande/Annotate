import XCTest

@testable import Annotate

@MainActor
final class RegionPickerTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
    private var picker: RegionPicker!
    private var picked: [CGRect] = []
    private var cancels = 0

    override func setUp() {
        super.setUp()
        picker = RegionPicker(frame: bounds)
        picked = []
        cancels = 0
        picker.onPick = { [unowned self] in self.picked.append($0) }
        picker.onCancel = { [unowned self] in self.cancels += 1 }
    }

    override func tearDown() {
        picker = nil
        super.tearDown()
    }

    private func chord(_ key: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> KeyChord {
        KeyChord(keyCode: keyCode, key: key, commandKey: nil, modifiers: modifiers, characters: key, isRepeat: false)
    }

    // MARK: - Geometry

    func testDragsInEveryDirectionGiveTheSameRect() {
        let expected = CGRect(x: 10, y: 20, width: 30, height: 40)
        let corners: [(NSPoint, NSPoint)] = [
            (NSPoint(x: 10, y: 20), NSPoint(x: 40, y: 60)),
            (NSPoint(x: 40, y: 60), NSPoint(x: 10, y: 20)),
            (NSPoint(x: 10, y: 60), NSPoint(x: 40, y: 20)),
            (NSPoint(x: 40, y: 20), NSPoint(x: 10, y: 60)),
        ]
        for (start, end) in corners {
            XCTAssertEqual(RegionPicker.normalizedRect(from: start, to: end, within: bounds), expected, "\(start) to \(end)")
        }
    }

    func testDragsPastTheEdgeStopAtTheDisplay() {
        let rect = RegionPicker.normalizedRect(from: NSPoint(x: 380, y: 290), to: NSPoint(x: 450, y: -20), within: bounds)
        XCTAssertEqual(rect, CGRect(x: 380, y: 0, width: 20, height: 290))
    }

    func testOnlyRectsAtLeastTheMinimumOnBothSidesArePickable() {
        let side = RegionPicker.minimumSide
        XCTAssertTrue(RegionPicker.isPickable(CGRect(x: 0, y: 0, width: side, height: side)))
        XCTAssertFalse(RegionPicker.isPickable(CGRect(x: 0, y: 0, width: side - 1, height: 100)))
        XCTAssertFalse(RegionPicker.isPickable(CGRect(x: 0, y: 0, width: 100, height: 0)))
    }

    func testSizeLabelShowsWholePoints() {
        XCTAssertEqual(RegionPicker.sizeText(for: CGRect(x: 0, y: 0, width: 120.4, height: 80.6)), "120 × 81")
    }

    func testSizeLabelStaysOnTheDisplay() {
        let size = CGSize(width: 60, height: 18)
        // Below the rect's bottom-right corner when there is room.
        let below = RegionPicker.labelFrame(size: size, for: CGRect(x: 100, y: 100, width: 80, height: 50), within: bounds)
        XCTAssertEqual(below.maxX, 180)
        XCTAssertLessThan(below.maxY, 100)
        // Inside the rect when it touches the bottom edge, and clamped to the left edge.
        let inside = RegionPicker.labelFrame(size: size, for: CGRect(x: 0, y: 0, width: 20, height: 50), within: bounds)
        XCTAssertGreaterThanOrEqual(inside.minY, 0)
        XCTAssertEqual(inside.minX, 0)
    }

    // MARK: - Mouse

    func testReleasePicksTheDraggedRect() {
        picker.mouseDown(at: NSPoint(x: 200, y: 150))
        picker.mouseDragged(to: NSPoint(x: 120, y: 200))
        XCTAssertEqual(picker.selection, CGRect(x: 120, y: 150, width: 80, height: 50))
        XCTAssertTrue(picked.isEmpty, "Nothing is picked until release")

        picker.mouseUp(at: NSPoint(x: 100, y: 210))

        XCTAssertEqual(picked, [CGRect(x: 100, y: 150, width: 100, height: 60)])
        XCTAssertEqual(cancels, 0)
    }

    func testAClickKeepsPicking() {
        picker.mouseDown(at: NSPoint(x: 50, y: 50))
        picker.mouseUp(at: NSPoint(x: 52, y: 51))

        XCTAssertTrue(picked.isEmpty)
        XCTAssertEqual(cancels, 0)
        XCTAssertNil(picker.selection, "The next press starts a fresh rect")

        picker.mouseDown(at: NSPoint(x: 10, y: 10))
        picker.mouseUp(at: NSPoint(x: 30, y: 40))
        XCTAssertEqual(picked, [CGRect(x: 10, y: 10, width: 20, height: 30)])
    }

    func testDragWithoutAPressDoesNothing() {
        picker.mouseDragged(to: NSPoint(x: 100, y: 100))
        picker.mouseUp(at: NSPoint(x: 200, y: 200))
        XCTAssertNil(picker.selection)
        XCTAssertTrue(picked.isEmpty)
    }

    func testRightClickCancels() throws {
        let event = try XCTUnwrap(TestEvents.createMouseEvent(type: .rightMouseDown, location: NSPoint(x: 10, y: 10)))
        picker.handleMouseEvent(event)
        XCTAssertEqual(cancels, 1)
        XCTAssertTrue(picked.isEmpty)
    }

    // MARK: - Keys

    func testEscapeCancels() {
        XCTAssertTrue(picker.handleKey(chord("\u{1b}", keyCode: 53)))
        XCTAssertEqual(cancels, 1)
    }

    func testOtherKeysAreSwallowedWithoutCancelling() {
        XCTAssertTrue(picker.handleKey(chord("p", keyCode: 35)))
        XCTAssertTrue(picker.handleKey(chord("s", keyCode: 1, modifiers: .command)))
        XCTAssertEqual(cancels, 0)
        XCTAssertTrue(picked.isEmpty)
    }
}
