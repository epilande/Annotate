import XCTest

@testable import Annotate

/// The status menu's Recent Captures submenu and its actions. Items are found by identifier,
/// never by position.
@MainActor
final class RecentCapturesMenuTests: XCTestCase {
    private var appDelegate: AppDelegate!
    private var testDefaults: UserDefaults!
    private var overlay: OverlayWindow!
    private var folder: URL!
    private var pasteboard: NSPasteboard!
    private var opened: [URL] = []
    private var revealed: [[URL]] = []
    private var alerts: [String] = []

    override func setUp() {
        super.setUp()
        TestWindows.recordOpenWindows()
        testDefaults = TestUserDefaults.create()
        BoardManager.shared = BoardManager(userDefaults: testDefaults)
        ShortcutManager.shared = ShortcutManager(userDefaults: testDefaults)
        appDelegate = AppDelegate(userDefaults: testDefaults)
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let screen = NSScreen.screens.first!
        overlay = appDelegate.overlayWindows[screen]
        appDelegate.pointerLocationOverride = NSPoint(x: screen.frame.midX, y: screen.frame.midY)

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentCapturesMenuTests-\(UUID().uuidString)", isDirectory: true)
        // Created by the first capture or file, and named by its real path, as scans name it.
        let real = realpath(FileManager.default.temporaryDirectory.path, nil)!
        folder = URL(fileURLWithPath: String(cString: real), isDirectory: true)
            .appendingPathComponent(temporary.lastPathComponent, isDirectory: true)
        free(real)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("RecentCapturesMenuTests-\(UUID().uuidString)"))
        let snapshot = CaptureTestImages.solid(width: 64, height: 32, RGBA(r: 0, g: 0, b: 255, a: 255))
        appDelegate.captureService = CaptureService(
            source: StubDisplayCapturing(snapshotImage: snapshot),
            sinks: [FileSink(folder: folder), ClipboardSink(pasteboard: pasteboard)])
        appDelegate.captureNotifier = StubCaptureNotifier()
        appDelegate.captureConfirmation.schedule = { _, _ in }
        appDelegate.announceForAccessibility = { _ in }
        appDelegate.showCaptureProblemAlert = { [unowned self] message, _ in self.alerts.append(message) }
        appDelegate.captureFileActions.open = { [unowned self] in
            self.opened.append($0)
            return true
        }
        appDelegate.captureFileActions.reveal = { [unowned self] in self.revealed.append($0) }
        appDelegate.captureFileActions.pasteboard = pasteboard
        opened = []
        revealed = []
        alerts = []
    }

    override func tearDown() {
        appDelegate.overlayWindows.values.forEach { $0.stopFadeLoop() }
        appDelegate.tearDownAfterLaunch()
        appDelegate = nil
        overlay = nil
        try? FileManager.default.removeItem(at: folder)
        pasteboard.releaseGlobally()
        assertNoLeakedWindows()
        TestUserDefaults.removeSuite()
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private var statusMenu: NSMenu { appDelegate.statusItem.menu! }

    private var recentItem: NSMenuItem? {
        statusMenu.items.first { $0.identifier == .recentCaptures }
    }

    private var submenu: NSMenu { recentItem!.submenu! }

    private func item(_ identifier: NSUserInterfaceItemIdentifier, in menu: NSMenu? = nil) -> NSMenuItem? {
        (menu ?? submenu).items.first { $0.identifier == identifier }
    }

    private var rows: [NSMenuItem] {
        submenu.items.filter { $0.identifier == .recentCapture }
    }

    private var listedFiles: [URL] {
        rows.compactMap { $0.representedObject as? URL }
    }

    /// The action `identifier` names in the row for `file`.
    private func action(_ identifier: NSUserInterfaceItemIdentifier, for file: URL) throws -> NSMenuItem {
        let row = try XCTUnwrap(rows.first { $0.representedObject as? URL == file })
        return try XCTUnwrap(item(identifier, in: try XCTUnwrap(row.submenu)))
    }

    /// A saved capture `index` seconds into the run, in the default folder.
    @discardableResult
    private func makeCapture(_ index: Int) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(
            FileSink.fileName("Annotate 2026-11-01 at 10.23.\(String(format: "%02d", index))", attempt: 1))
        try Data([0x89, 0x50, 0x4E, 0x47, UInt8(index)]).write(to: file)
        try FileManager.default.setAttributes(
            [.creationDate: Date().addingTimeInterval(-3600 + TimeInterval(index))], ofItemAtPath: file.path)
        return file
    }

    /// Opens the status menu, as a click does, and waits for its scan to land.
    private func openStatusMenu() async {
        appDelegate.menuWillOpen(statusMenu)
        await appDelegate.recentCaptures.scanTask?.value
        appDelegate.menuDidClose(statusMenu)
    }

    private func finishCaptures() async {
        await appDelegate.captureTask?.value
        await appDelegate.recentCaptures.thumbnailTask?.value
        runLoop { !self.appDelegate.isPresentingCaptureProblems }
    }

    private func runLoop(until condition: () -> Bool, timeout: TimeInterval = 3) {
        let deadline = CACurrentMediaTime() + timeout
        while !condition(), CACurrentMediaTime() < deadline {
            wait(for: 0.01)
        }
    }

    /// Whether AppKit draws the item's image when the menu opens. macOS 27 hides menu item
    /// images by default in apps built with its SDK, so a row can hold its thumbnail and still
    /// show none.
    private func drawsImage(_ item: NSMenuItem) -> Bool {
        guard item.image != nil else { return false }
        #if compiler(>=6.4)
            if #available(macOS 27, *) {
                return item.preferredImageVisibility == .visible
            }
        #endif
        return true
    }

    private func allItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(allItems(in:)) ?? []) }
    }

    // MARK: - Layout

    func testRecentCapturesComesRightAfterCaptureArea() throws {
        let items = statusMenu.items
        let captureArea = try XCTUnwrap(items.firstIndex { $0.action == #selector(AppDelegate.captureArea) })
        let recent = try XCTUnwrap(items.firstIndex { $0.identifier == .recentCaptures })

        XCTAssertEqual(recent, captureArea + 1)
        XCTAssertEqual(items[recent].title, "Recent Captures")
        XCTAssertNotNil(items[recent].submenu)
        XCTAssertTrue(submenu.delegate === appDelegate.recentCapturesMenu)
    }

    func testThumbnailsAppearOnlyInsideTheSubmenu() async throws {
        try makeCapture(1)
        await openStatusMenu()

        XCTAssertEqual(rows.count, 1)
        XCTAssertNotNil(rows.first?.image)
        XCTAssertEqual(rows.first?.image?.size, RecentCaptureThumbnail.box)
        XCTAssertTrue(try drawsImage(XCTUnwrap(rows.first)), "AppKit would hide the thumbnail")
        XCTAssertNil(recentItem?.image)
        XCTAssertFalse(statusMenu.items.contains { $0.identifier == .recentCapture })
    }

    func testEmptyMenuSaysSoAndHidesClearMenu() throws {
        let empty = try XCTUnwrap(item(.noRecentCaptures))
        XCTAssertEqual(empty.title, "No Recent Captures")
        XCTAssertFalse(empty.isEnabled)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertTrue(try XCTUnwrap(item(.openCaptureFolder)).isEnabled)
        XCTAssertTrue(try XCTUnwrap(item(.clearRecentCaptures)).isHidden)
        XCTAssertNil(item(.unreachableCaptureFolder))
        let index = { (id: NSUserInterfaceItemIdentifier) in self.submenu.items.firstIndex { $0.identifier == id } }
        XCTAssertLessThan(try XCTUnwrap(index(.noRecentCaptures)), try XCTUnwrap(index(.openCaptureFolder)))
    }

    func testListsTheEightNewestNewestFirstThenTheFolderActions() async throws {
        let files = try (0..<10).map { try makeCapture($0) }

        await openStatusMenu()

        XCTAssertEqual(listedFiles, Array(files.reversed().prefix(8)))
        XCTAssertNil(item(.noRecentCaptures))
        XCTAssertFalse(try XCTUnwrap(item(.clearRecentCaptures)).isHidden)
        let rowIndexes = submenu.items.indices.filter { submenu.items[$0].identifier == .recentCapture }
        let folderIndex = try XCTUnwrap(submenu.items.firstIndex { $0.identifier == .openCaptureFolder })
        let clearIndex = try XCTUnwrap(submenu.items.firstIndex { $0.identifier == .clearRecentCaptures })
        XCTAssertLessThan(try XCTUnwrap(rowIndexes.last), folderIndex)
        XCTAssertLessThan(folderIndex, clearIndex)
    }

    func testEachRowHasCopyOpenAndShowInFinder() async throws {
        let file = try makeCapture(1)
        await openStatusMenu()

        let row = try XCTUnwrap(rows.first)
        let actions = try XCTUnwrap(row.submenu)

        XCTAssertEqual(actions.items.map(\.title), ["Copy", "Open", "Show in Finder"])
        XCTAssertTrue(actions.items.allSatisfy { $0.representedObject as? URL == file && $0.target === appDelegate })
        XCTAssertEqual(row.toolTip, "\(file.lastPathComponent)\n\(CaptureSettingsView.displayPath(of: folder))")
        XCTAssertEqual(row.accessibilityHelp(), row.toolTip)
    }

    func testNothingInTheSubmenuHasAKeyEquivalent() async throws {
        try makeCapture(1)
        await openStatusMenu()

        let items = allItems(in: submenu)
        XCTAssertGreaterThan(items.count, 4)
        for item in items {
            XCTAssertEqual(item.keyEquivalent, "", item.title)
        }
        XCTAssertEqual(recentItem?.keyEquivalent, "")
    }

    func testTitleIsTheRelativeDayAndTime() throws {
        let locale = Locale(identifier: "en_US")
        let title = RecentCapturesMenu.title(for: Date(), locale: locale)
        XCTAssertTrue(title.hasPrefix("Today at "), title)
        XCTAssertTrue(title.hasSuffix("AM") || title.hasSuffix("PM"), title)
        // A calendar day back, which isn't always 24 hours across a daylight saving change.
        let dayBefore = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let yesterday = RecentCapturesMenu.title(for: dayBefore, locale: locale)
        XCTAssertTrue(yesterday.hasPrefix("Yesterday at "), yesterday)
    }

    func testUnreachableChosenFolderShowsANoteAndTheDefaultFolder() async throws {
        let file = try makeCapture(1)
        let chosen = folder.deletingLastPathComponent()
            .appendingPathComponent("RecentCapturesMenuTests-Shots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        try appDelegate.captureFolders.choose(chosen)
        try FileManager.default.removeItem(at: chosen)

        await openStatusMenu()

        let note = try XCTUnwrap(item(.unreachableCaptureFolder))
        XCTAssertEqual(note.title, "Can't reach \(chosen.lastPathComponent). Showing the default folder")
        XCTAssertFalse(note.isEnabled)
        XCTAssertEqual(submenu.items.first, note)
        XCTAssertEqual(listedFiles, [file])
    }

    func testUnreachableNoteFollowsTheChosenFolder() async throws {
        let file = try makeCapture(1)
        let listed = [RecentCapture(file: file, createdAt: Date())]
        appDelegate.recentCaptures.scan = { _, _, _, _ in RecentCaptureScan(captures: listed, missedFolder: "Shots") }
        await openStatusMenu()
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(item(.unreachableCaptureFolder)?.title, "Can't reach Shots. Showing the default folder")

        appDelegate.recentCaptures.scan = { _, _, _, _ in RecentCaptureScan(captures: listed, missedFolder: "Archive") }
        await openStatusMenu()

        XCTAssertEqual(item(.unreachableCaptureFolder)?.title, "Can't reach Archive. Showing the default folder")
        XCTAssertTrue(rows.first === row, "The same captures keep their rows")
        XCTAssertEqual(submenu.items.filter { $0.identifier == .unreachableCaptureFolder }.count, 1)
    }

    func testClosingTheSubmenuLeavesOverlaysUnderTheStatusMenu() throws {
        appDelegate.showInteractiveOverlay()
        appDelegate.menuWillOpen(statusMenu)
        XCTAssertEqual(overlay.level, OverlayWindow.menuOpenLevel)

        XCTAssertFalse(submenu.delegate === appDelegate, "The status menu's delegate raises the overlays on close")
        submenu.delegate?.menuWillOpen?(submenu)
        submenu.delegate?.menuDidClose?(submenu)

        XCTAssertEqual(overlay.level, OverlayWindow.menuOpenLevel, "The status menu is still open over it")
        appDelegate.menuDidClose(statusMenu)
        XCTAssertEqual(overlay.level, OverlayWindow.elevatedLevel)
    }

    // MARK: - Updates

    func testAFreshCaptureIsListedAtOnce() async throws {
        appDelegate.captureScreen()
        await finishCaptures()

        let saved = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: folder.path).first)
        XCTAssertEqual(listedFiles.map(\.lastPathComponent), [saved], "No scan needed")
        XCTAssertNil(appDelegate.recentCaptures.scanTask)
        XCTAssertNotNil(appDelegate.recentCaptures.thumbnail(for: try XCTUnwrap(appDelegate.recentCaptures.captures.first)))
    }

    func testACaptureThatSavedButCouldntCopyIsListedToo() async throws {
        appDelegate.captureService = CaptureService(
            source: StubDisplayCapturing(snapshotImage: CaptureTestImages.solid(width: 8, height: 8, RGBA(r: 0, g: 0, b: 0, a: 255))),
            sinks: [FileSink(folder: folder), FailingSink(destination: .clipboard)])

        appDelegate.captureScreen()
        await finishCaptures()

        XCTAssertEqual(alerts.count, 1, "The problem is still reported")
        XCTAssertEqual(rows.count, 1)
    }

    func testAScanLandingWithTheSameCapturesUpdatesRowsInPlace() async throws {
        try makeCapture(1)
        try makeCapture(2)
        await openStatusMenu()
        let before = rows

        await openStatusMenu()

        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(zip(before, rows).allSatisfy { $0 === $1 }, "An open actions submenu stays open")
        XCTAssertTrue(rows.allSatisfy(drawsImage))
        let newer = try makeCapture(3)
        await openStatusMenu()
        XCTAssertEqual(listedFiles.first, newer)
    }

    // MARK: - Actions

    func testCopyPutsTheCaptureOnTheClipboard() async throws {
        let file = try makeCapture(1)
        await openStatusMenu()

        appDelegate.copyRecentCapture(try action(.copyRecentCapture, for: file))
        await appDelegate.recentCaptureCopyTask?.value

        XCTAssertEqual(pasteboard.data(forType: .png), try Data(contentsOf: file))
        XCTAssertTrue(alerts.isEmpty)
    }

    func testCopyOfAVanishedCaptureDropsItSilently() async throws {
        let file = try makeCapture(1)
        await openStatusMenu()
        try FileManager.default.removeItem(at: file)

        appDelegate.copyRecentCapture(try action(.copyRecentCapture, for: file))
        await appDelegate.recentCaptureCopyTask?.value
        runLoop { !self.appDelegate.isPresentingCaptureProblems }

        XCTAssertTrue(rows.isEmpty)
        XCTAssertNotNil(item(.noRecentCaptures))
        XCTAssertTrue(alerts.isEmpty)
    }

    func testOverlappingCopiesLeaveTheLastPickOnTheClipboard() async throws {
        let first = try makeCapture(1)
        let second = try makeCapture(2)
        await openStatusMenu()
        let gate = DispatchSemaphore(value: 0)
        let slowName = first.lastPathComponent
        appDelegate.captureFileActions.readFile = { url in
            // The first pick reads slowly, so without ordering it would land last.
            if url.lastPathComponent == slowName { gate.wait() }
            return try Data(contentsOf: url)
        }

        appDelegate.copyRecentCapture(try action(.copyRecentCapture, for: first))
        let firstCopy = appDelegate.recentCaptureCopyTask
        appDelegate.copyRecentCapture(try action(.copyRecentCapture, for: second))
        let secondCopy = appDelegate.recentCaptureCopyTask
        try await Task.sleep(for: .milliseconds(200))
        gate.signal()
        await firstCopy?.value
        await secondCopy?.value

        XCTAssertEqual(pasteboard.data(forType: .png), try Data(contentsOf: second))
        XCTAssertTrue(alerts.isEmpty)
    }

    func testCopyFailureShowsTheCaptureAlert() async throws {
        let file = try makeCapture(1)
        await openStatusMenu()
        appDelegate.captureFileActions.readFile = { _ in throw CocoaError(.fileReadNoPermission) }

        appDelegate.copyRecentCapture(try action(.copyRecentCapture, for: file))
        await appDelegate.recentCaptureCopyTask?.value
        runLoop { !self.appDelegate.isPresentingCaptureProblems }

        XCTAssertEqual(alerts, ["Couldn't Copy \(file.lastPathComponent)"])
        XCTAssertEqual(listedFiles, [file], "The file is still there")
    }

    func testOpenClosesTheInteractiveOverlayAndKeepsItsDrawings() async throws {
        let file = try makeCapture(1)
        await openStatusMenu()
        testDefaults.settings[.clearDrawingsOnStart] = true
        appDelegate.showInteractiveOverlay()
        overlay.overlayView.paths.append(TestFactory.createDrawingPath())

        appDelegate.openRecentCapture(try action(.openRecentCapture, for: file))

        XCTAssertEqual(opened, [file])
        XCTAssertFalse(appDelegate.isInteractiveOverlayOpen)
        appDelegate.showInteractiveOverlay()
        XCTAssertEqual(overlay.overlayView.paths.count, 1)
    }

    func testOpenLeavesAlwaysOnOverlaysUp() async throws {
        let file = try makeCapture(1)
        await openStatusMenu()
        appDelegate.toggleAlwaysOnMode()

        appDelegate.openRecentCapture(try action(.openRecentCapture, for: file))

        XCTAssertEqual(opened, [file])
        XCTAssertTrue(appDelegate.alwaysOnMode)
        XCTAssertTrue(overlay.isVisible)
    }

    func testOpenOfAVanishedCaptureDropsItAndLeavesTheOverlay() async throws {
        let file = try makeCapture(1)
        await openStatusMenu()
        appDelegate.showInteractiveOverlay()
        try FileManager.default.removeItem(at: file)

        appDelegate.openRecentCapture(try action(.openRecentCapture, for: file))

        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(appDelegate.isInteractiveOverlayOpen)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testShowInFinderRevealsTheCaptureAndClosesTheOverlay() async throws {
        let file = try makeCapture(1)
        await openStatusMenu()
        appDelegate.showInteractiveOverlay()

        appDelegate.showRecentCaptureInFinder(try action(.showRecentCaptureInFinder, for: file))

        XCTAssertEqual(revealed, [[file]])
        XCTAssertFalse(appDelegate.isInteractiveOverlayOpen)
    }

    func testShowInFinderForAVanishedCaptureChecksBeforeClosingTheOverlay() async throws {
        let file = try makeCapture(1)
        await openStatusMenu()
        appDelegate.showInteractiveOverlay()
        try FileManager.default.removeItem(at: file)

        appDelegate.showRecentCaptureInFinder(try action(.showRecentCaptureInFinder, for: file))

        XCTAssertTrue(revealed.isEmpty)
        XCTAssertTrue(appDelegate.isInteractiveOverlayOpen)
        XCTAssertTrue(rows.isEmpty)
    }

    func testOpenCaptureFolderCreatesTheDefaultFolderAndClosesTheOverlay() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        appDelegate.showInteractiveOverlay()

        appDelegate.openCaptureFolder(try XCTUnwrap(item(.openCaptureFolder)))

        XCTAssertEqual(opened.map(\.path), [folder.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertFalse(appDelegate.isInteractiveOverlayOpen)
    }

    func testOpenCaptureFolderOpensTheChosenFolder() throws {
        let chosen = folder.deletingLastPathComponent()
            .appendingPathComponent("RecentCapturesMenuTests-Chosen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: chosen) }
        try appDelegate.captureFolders.choose(chosen)

        appDelegate.openCaptureFolder(nil)

        XCTAssertEqual(opened.map(\.lastPathComponent), [chosen.lastPathComponent])
    }

    func testClearMenuEmptiesTheMenuAndKeepsTheFiles() async throws {
        let file = try makeCapture(1)
        await openStatusMenu()
        XCTAssertEqual(rows.count, 1)

        appDelegate.clearRecentCaptures(try XCTUnwrap(item(.clearRecentCaptures)))

        XCTAssertTrue(rows.isEmpty)
        XCTAssertTrue(try XCTUnwrap(item(.clearRecentCaptures)).isHidden)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        await openStatusMenu()
        XCTAssertTrue(rows.isEmpty, "A rescan stays cleared")

        appDelegate.captureScreen()
        await finishCaptures()
        XCTAssertEqual(rows.count, 1, "A capture after Clear Menu appears")
    }
}
