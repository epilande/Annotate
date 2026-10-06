import XCTest

@testable import Annotate

@MainActor
final class ScreenshotSelectionTests: XCTestCase {
    private let screenshotPID: pid_t = 4242
    private let screenSizes = [CGSize(width: 1440, height: 2560), CGSize(width: 1920, height: 1080)]

    private func window(pid: pid_t, owner: String = "Screenshot", width: CGFloat, height: CGFloat) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: pid,
            kCGWindowOwnerName as String: owner,
            kCGWindowBounds as String: CGRect(x: 0, y: 0, width: width, height: height).dictionaryRepresentation,
        ]
    }

    func testFullScreenScreenshotWindowIsTheSelection() {
        XCTAssertTrue(ScreenshotSelection.containsSelectionWindow(
            [window(pid: screenshotPID, width: 1920, height: 1080)],
            ownerPIDs: [screenshotPID],
            screenSizes: screenSizes
        ))
    }

    func testToolbarAndThumbnailWindowsAreNotTheSelection() {
        XCTAssertFalse(ScreenshotSelection.containsSelectionWindow(
            [
                window(pid: screenshotPID, width: 800, height: 50),
                window(pid: screenshotPID, width: 300, height: 200),
            ],
            ownerPIDs: [screenshotPID],
            screenSizes: screenSizes
        ))
    }

    func testFullScreenWindowFromAnotherAppIsNotTheSelection() {
        XCTAssertFalse(ScreenshotSelection.containsSelectionWindow(
            [window(pid: 99, owner: "Keynote", width: 1920, height: 1080)],
            ownerPIDs: [screenshotPID],
            screenSizes: screenSizes
        ))
    }
}
