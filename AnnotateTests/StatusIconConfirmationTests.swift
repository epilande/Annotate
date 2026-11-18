import XCTest

@testable import Annotate

@MainActor
final class StatusIconConfirmationTests: XCTestCase {
    /// Expiries the confirmation scheduled, in order, which the tests run by hand.
    private var expiries: [(delay: TimeInterval, run: @MainActor () -> Void)] = []
    /// Whether the checkmark was up each time `onChange` ran.
    private var changes: [Bool] = []
    private var confirmation: StatusIconConfirmation!

    override func setUp() {
        super.setUp()
        expiries = []
        changes = []
        confirmation = StatusIconConfirmation(
            duration: 1.5,
            schedule: { [unowned self] delay, action in self.expiries.append((delay, action)) },
            onChange: { [unowned self] in self.changes.append(self.confirmation.isShowing) })
    }

    override func tearDown() {
        confirmation = nil
        super.tearDown()
    }

    func testShowPutsTheCheckmarkUpAndItsExpiryTakesItDown() throws {
        confirmation.show()

        XCTAssertTrue(confirmation.isShowing)
        XCTAssertEqual(changes, [true])
        XCTAssertEqual(expiries.map(\.delay), [1.5])

        try XCTUnwrap(expiries.first).run()

        XCTAssertFalse(confirmation.isShowing)
        XCTAssertEqual(changes, [true, false])
    }

    func testShowingAgainRestartsTheTimeWithoutRedrawing() {
        confirmation.show()
        confirmation.show()

        XCTAssertEqual(changes, [true], "The checkmark is already up")
        XCTAssertEqual(expiries.count, 2)

        expiries[0].run()
        XCTAssertTrue(confirmation.isShowing, "The first show's time no longer counts")
        XCTAssertEqual(changes, [true])

        expiries[1].run()
        XCTAssertFalse(confirmation.isShowing)
        XCTAssertEqual(changes, [true, false])
    }

    func testExpiriesRunOutOfOrderStillEndOnTheLatest() {
        confirmation.show()
        confirmation.show()
        confirmation.show()

        expiries[2].run()
        expiries[0].run()
        expiries[1].run()

        XCTAssertFalse(confirmation.isShowing)
        XCTAssertEqual(changes, [true, false], "Ends once, and the stale expiries do nothing")
    }

    func testEndTakesTheCheckmarkDownAndIgnoresItsPendingExpiry() {
        confirmation.show()
        confirmation.end()

        XCTAssertFalse(confirmation.isShowing)
        XCTAssertEqual(changes, [true, false])

        confirmation.show()
        expiries[0].run()
        XCTAssertTrue(confirmation.isShowing, "The expiry from before the end belongs to an older show")

        expiries[1].run()
        XCTAssertFalse(confirmation.isShowing)
        XCTAssertEqual(changes, [true, false, true, false])
    }

    func testEndingWhenNothingShowsDoesNothing() {
        confirmation.end()

        XCTAssertFalse(confirmation.isShowing)
        XCTAssertTrue(changes.isEmpty)
    }

    func testAnExpiryAfterTheConfirmationIsGoneDoesNothing() throws {
        confirmation.show()
        let expiry = try XCTUnwrap(expiries.first).run
        confirmation = nil

        expiry()

        XCTAssertEqual(changes, [true])
    }

    func testTheRunLoopTimerEndsTheCheckmarkOnItsOwn() {
        var ended = false
        let realTime = StatusIconConfirmation(duration: 0.05) { ended = true }
        realTime.show()
        ended = false

        let deadline = CACurrentMediaTime() + 3
        while realTime.isShowing, CACurrentMediaTime() < deadline {
            wait(for: 0.01)
        }

        XCTAssertFalse(realTime.isShowing)
        XCTAssertTrue(ended)
    }

    // MARK: - What a capture confirms

    func testCaptureConfirmationSaysSavedForAFileAndCopiedForTheClipboardOnly() {
        let capture = makeCapture()
        let file = URL(fileURLWithPath: "/tmp/Annotate.png")
        let saved = CaptureResult(capture: capture, png: Data(), deliveries: [.file(file)], failures: [])
        let both = CaptureResult(capture: capture, png: Data(), deliveries: [.file(file), .clipboard], failures: [])
        let copied = CaptureResult(capture: capture, png: Data(), deliveries: [.clipboard], failures: [])
        let nowhere = CaptureResult(capture: capture, png: Data(), deliveries: [], failures: [])

        XCTAssertEqual(CaptureConfirmation(saved)?.announcement, "Capture saved")
        XCTAssertEqual(CaptureConfirmation(both)?.announcement, "Capture saved")
        XCTAssertEqual(CaptureConfirmation(copied)?.announcement, "Capture copied")
        XCTAssertNil(CaptureConfirmation(nowhere))
    }

    func testTheCheckmarkAndThePencilLookDifferent() throws {
        let pencil = try XCTUnwrap(AppDelegate.statusIcon(color: .gray, symbolName: "pencil", description: "Annotate"))
        let check = try XCTUnwrap(
            AppDelegate.statusIcon(color: .gray, symbolName: "checkmark", description: "Capture saved"))

        XCTAssertNotEqual(pencil.tiffRepresentation, check.tiffRepresentation)
        XCTAssertEqual(pencil.accessibilityDescription, "Annotate")
        XCTAssertEqual(check.accessibilityDescription, "Capture saved")
    }

    private func makeCapture() -> Capture {
        Capture(
            image: CaptureTestImages.solid(width: 4, height: 4, RGBA(r: 0, g: 0, b: 255, a: 255)),
            display: DisplayInfo(id: 7, frame: CGRect(x: 0, y: 0, width: 4, height: 4), scale: 1),
            region: CGRect(x: 0, y: 0, width: 4, height: 4),
            scene: nil,
            capturedAt: Date(timeIntervalSince1970: 0),
            hostTime: 0)
    }
}
