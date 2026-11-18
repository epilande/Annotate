import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import Annotate

/// Holds each scan a `RecentCaptureStore` starts until the test lets it land, with what the
/// test says it found.
@MainActor
final class HeldScans {
    private var waiting: [CheckedContinuation<RecentCaptureScan, Never>] = []

    var count: Int { waiting.count }

    /// Installs itself as `store`'s scanner.
    func hold(_ store: RecentCaptureStore) {
        store.scan = { [weak self] _, _, _, _ in
            await withCheckedContinuation { continuation in
                Task { @MainActor in self?.waiting.append(continuation) }
            }
        }
    }

    /// Lands the `index`th scan held so far.
    func land(_ index: Int, with scan: RecentCaptureScan) {
        waiting[index].resume(returning: scan)
    }
}

/// The scanner, thumbnails, store, and file actions behind the status menu's Recent Captures.
/// The menu itself is in `RecentCapturesMenuTests`.
@MainActor
final class RecentCapturesTests: XCTestCase {
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = TestUserDefaults.create()
    }

    override func tearDown() {
        TestUserDefaults.removeSuite()
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    /// A new folder, by its real path (`/private/var`, not `/var`), removed after the test.
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentCapturesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let real = try XCTUnwrap(realpath(folder.path, nil))
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real), isDirectory: true)
    }

    private static func pngData(width: Int = 4, height: Int = 4) -> Data {
        let image = CaptureTestImages.solid(width: width, height: height, RGBA(r: 0, g: 0, b: 255, a: 255))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// A PNG named `name` in `folder`, created `secondsAfterBase` seconds after `base`.
    @discardableResult
    private func makeFile(
        _ name: String, in folder: URL, secondsAfterBase: TimeInterval = 0, width: Int = 4, height: Int = 4
    ) throws -> URL {
        let file = folder.appendingPathComponent(name, isDirectory: false)
        try Self.pngData(width: width, height: height).write(to: file)
        try FileManager.default.setAttributes(
            [.creationDate: Self.base.addingTimeInterval(secondsAfterBase)], ofItemAtPath: file.path)
        return file
    }

    /// The capture name `FileSink` gives the `index`th second of a run.
    private static func name(_ index: Int, copy: Int = 1) -> String {
        FileSink.fileName("Annotate 2026-11-01 at 10.23.\(String(format: "%02d", index))", attempt: copy)
    }

    private func store(chosen: CaptureFolderStore? = nil, defaultFolder: URL) -> RecentCaptureStore {
        let folders = chosen ?? CaptureFolderStore(settings: testDefaults.settings)
        return RecentCaptureStore(settings: testDefaults.settings) { (folders, defaultFolder) }
    }

    private func settle(_ store: RecentCaptureStore) async {
        await store.scanTask?.value
        await store.thumbnailTask?.value
    }

    private func result(saving file: URL?, copied: Bool = true, image: CGImage? = nil) -> CaptureResult {
        let image = image ?? CaptureTestImages.solid(width: 400, height: 200, RGBA(r: 255, g: 0, b: 0, a: 255))
        let capture = Capture(
            image: image,
            display: DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 400, height: 200), scale: 1),
            region: CGRect(x: 0, y: 0, width: 400, height: 200),
            scene: nil,
            capturedAt: Self.base,
            hostTime: 0)
        var deliveries: [CaptureDelivery] = []
        if let file { deliveries.append(.file(file)) }
        if copied { deliveries.append(.clipboard) }
        return CaptureResult(capture: capture, png: Data(), deliveries: deliveries, failures: [])
    }

    private func names(_ captures: [RecentCapture]) -> [String] {
        captures.map(\.file.lastPathComponent)
    }

    // MARK: - Names

    func testCaptureNamesAreTheOnesFileSinkGives() {
        XCTAssertEqual(
            RecentCaptureScanner.parse("Annotate 2026-11-01 at 10.23.45.png"),
            .init(stamp: "2026-11-01 at 10.23.45", copy: 1))
        XCTAssertEqual(
            RecentCaptureScanner.parse("Annotate 2026-11-01 at 10.23.45 (2).png"),
            .init(stamp: "2026-11-01 at 10.23.45", copy: 2))
        XCTAssertEqual(RecentCaptureScanner.parse(FileSink.fileName("Annotate 2026-11-01 at 10.23.45", attempt: 1000))?.copy, 1000)
        XCTAssertNotNil(RecentCaptureScanner.parse(FileSink.fileName(FileSink.baseName(for: Date()), attempt: 1)))
    }

    func testOtherNamesAreNotCaptures() {
        let names = [
            FileSink.temporaryFileName(),
            ".Annotate 2026-11-01 at 10.23.45.png",
            "Annotate 2026-11-01 at 10.23.45.json",
            "Annotate 2026-11-01 at 10.23.45.PNG",
            "Annotate 2026-11-01 at 10.23.45 (1).png",
            "Annotate 2026-11-01 at 10.23.45 (02).png",
            "Annotate 2026-11-01 at 10.23.45 ().png",
            "Annotate 2026-11-01 at 10.23.45 copy.png",
            "Annotate 2026-11-1 at 10.23.45.png",
            "Annotate 2026-11-01 10.23.45.png",
            "annotate 2026-11-01 at 10.23.45.png",
            "Screenshot 2026-11-01 at 10.23.45.png",
            "Annotate.png",
        ]
        for name in names {
            XCTAssertNil(RecentCaptureScanner.parse(name), name)
        }
    }

    // MARK: - Scanner

    func testScanSortsByCreationDateNewestFirst() throws {
        let folder = try makeFolder()
        // Created out of name order: the creation date decides.
        try makeFile(Self.name(1), in: folder, secondsAfterBase: 30)
        try makeFile(Self.name(2), in: folder, secondsAfterBase: 10)
        try makeFile(Self.name(3), in: folder, secondsAfterBase: 20)

        let found = RecentCaptureScanner.captures(in: [folder], after: .distantPast)

        XCTAssertEqual(names(found), [Self.name(1), Self.name(3), Self.name(2)])
        XCTAssertEqual(found.first?.createdAt, Self.base.addingTimeInterval(30))
    }

    func testCopiesMadeInTheSameSecondListTheHigherCopyFirst() throws {
        let folder = try makeFolder()
        try makeFile(Self.name(1), in: folder)
        try makeFile(Self.name(1, copy: 2), in: folder)
        try makeFile(Self.name(1, copy: 3), in: folder)

        let found = RecentCaptureScanner.captures(in: [folder], after: .distantPast)

        XCTAssertEqual(names(found), [Self.name(1, copy: 3), Self.name(1, copy: 2), Self.name(1)])
    }

    func testScanListsTheEightNewest() throws {
        let folder = try makeFolder()
        for index in 0..<10 {
            try makeFile(Self.name(index), in: folder, secondsAfterBase: TimeInterval(index))
        }

        let found = RecentCaptureScanner.captures(in: [folder], after: .distantPast)

        XCTAssertEqual(RecentCaptureScanner.limit, 8)
        XCTAssertEqual(names(found), (2..<10).reversed().map { Self.name($0) })
    }

    func testScanMergesTwoFoldersAndCountsAFileOnce() throws {
        let chosen = try makeFolder()
        let standard = try makeFolder()
        try makeFile(Self.name(1), in: chosen, secondsAfterBase: 1)
        try makeFile(Self.name(2), in: standard, secondsAfterBase: 2)
        // The same folder through a symlink, as a chosen folder can be the default one.
        let link = try makeFolder().appendingPathComponent("Link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: standard)

        let found = RecentCaptureScanner.captures(in: [chosen, standard, link], after: .distantPast)

        XCTAssertEqual(names(found), [Self.name(2), Self.name(1)])
    }

    func testMissingFolderAddsNothing() throws {
        let folder = try makeFolder()
        try makeFile(Self.name(1), in: folder)
        let missing = folder.appendingPathComponent("Missing", isDirectory: true)

        XCTAssertEqual(names(RecentCaptureScanner.captures(in: [missing, folder], after: .distantPast)), [Self.name(1)])
        XCTAssertTrue(RecentCaptureScanner.captures(in: [missing], after: .distantPast).isEmpty)
    }

    func testHiddenTemporaryFilesForeignPNGsAndFoldersAreSkipped() throws {
        let folder = try makeFolder()
        try makeFile(Self.name(1), in: folder)
        try makeFile(FileSink.temporaryFileName(), in: folder, secondsAfterBase: 5)
        try makeFile(".\(Self.name(2))", in: folder, secondsAfterBase: 5)
        try makeFile("Holiday.png", in: folder, secondsAfterBase: 5)
        // A capture the user renamed drops out.
        try makeFile("Annotate 2026-11-01 at 10.23.03 edited.png", in: folder, secondsAfterBase: 5)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent(Self.name(4), isDirectory: true), withIntermediateDirectories: true)

        XCTAssertEqual(names(RecentCaptureScanner.captures(in: [folder], after: .distantPast)), [Self.name(1)])
    }

    func testScanHidesCapturesAtOrBeforeTheCutoff() throws {
        let folder = try makeFolder()
        try makeFile(Self.name(1), in: folder, secondsAfterBase: 0)
        try makeFile(Self.name(2), in: folder, secondsAfterBase: 10)
        try makeFile(Self.name(3), in: folder, secondsAfterBase: 20)

        let found = RecentCaptureScanner.captures(in: [folder], after: Self.base.addingTimeInterval(10))

        XCTAssertEqual(names(found), [Self.name(3)])
    }

    func testScanOfAnUnreachableChosenFolderNamesItAndListsTheDefaultFolder() async throws {
        let standard = try makeFolder()
        try makeFile(Self.name(1), in: standard)
        let chosen = try makeFolder().appendingPathComponent("Shots", isDirectory: true)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        let bookmark = try CaptureFolderBookmark.make(for: chosen)
        try FileManager.default.removeItem(at: chosen)

        let scan = await RecentCaptureScanner.scan(
            chosenFolder: bookmark, defaultFolder: standard, after: .distantPast, thumbnailed: [:])

        XCTAssertEqual(scan.missedFolder, "Shots")
        XCTAssertEqual(names(scan.captures), [Self.name(1)])
    }

    func testScanMakesOnlyTheMissingThumbnails() async throws {
        let folder = try makeFolder()
        let old = try makeFile(Self.name(1), in: folder, secondsAfterBase: 1)
        let new = try makeFile(Self.name(2), in: folder, secondsAfterBase: 2)

        let thumbnailed = [old.path: try XCTUnwrap(FileVersion.of(old))]
        let scan = await RecentCaptureScanner.scan(
            chosenFolder: nil, defaultFolder: folder, after: .distantPast, thumbnailed: thumbnailed)

        XCTAssertNil(scan.missedFolder)
        XCTAssertEqual(Set(scan.thumbnails.keys), [new.path])
    }

    func testScanRemakesTheThumbnailOfAFileThatChanged() async throws {
        let folder = try makeFolder()
        let file = try makeFile(Self.name(1), in: folder)
        let before = try XCTUnwrap(FileVersion.of(file))
        try makeFile(Self.name(1), in: folder, width: 40, height: 20)
        XCTAssertNotEqual(FileVersion.of(file), before)

        let scan = await RecentCaptureScanner.scan(
            chosenFolder: nil, defaultFolder: folder, after: .distantPast, thumbnailed: [file.path: before])

        let thumbnail = try XCTUnwrap(scan.thumbnails[file.path]?.image)
        XCTAssertEqual([thumbnail.width, thumbnail.height], [40, 20])
    }

    // MARK: - Thumbnails

    func testThumbnailsFitTheBoxAtTwoXWithoutUpscaling() {
        let fit = RecentCaptureThumbnail.fittedPixelSize(for:)
        XCTAssertEqual(RecentCaptureThumbnail.box, NSSize(width: 64, height: 40))
        XCTAssertEqual(fit(CGSize(width: 4000, height: 1000)), CGSize(width: 128, height: 32), "Wide")
        XCTAssertEqual(fit(CGSize(width: 1000, height: 4000)), CGSize(width: 20, height: 80), "Tall")
        XCTAssertEqual(fit(CGSize(width: 2560, height: 1600)), CGSize(width: 128, height: 80), "The box's shape")
        XCTAssertEqual(fit(CGSize(width: 50, height: 30)), CGSize(width: 50, height: 30), "Tiny, never upscaled")
        XCTAssertEqual(fit(CGSize(width: 10_000, height: 1)), CGSize(width: 128, height: 1), "At least a pixel")
        XCTAssertEqual(fit(.zero), .zero)
    }

    func testThumbnailFromAFileIsDownsampledAndNeverUpscaled() throws {
        let folder = try makeFolder()
        let wide = try makeFile(Self.name(1), in: folder, width: 1000, height: 250)
        let tiny = try makeFile(Self.name(2), in: folder, width: 50, height: 30)

        let wideThumbnail = try XCTUnwrap(RecentCaptureThumbnail.make(fromFileAt: wide))
        let tinyThumbnail = try XCTUnwrap(RecentCaptureThumbnail.make(fromFileAt: tiny))

        XCTAssertEqual([wideThumbnail.width, wideThumbnail.height], [128, 32])
        XCTAssertEqual([tinyThumbnail.width, tinyThumbnail.height], [50, 30])
        XCTAssertNil(RecentCaptureThumbnail.make(fromFileAt: folder.appendingPathComponent("Missing.png")))
    }

    func testThumbnailFromACaptureImageFitsTheBox() throws {
        let tall = CaptureTestImages.solid(width: 200, height: 800, RGBA(r: 0, g: 255, b: 0, a: 255))
        let tiny = CaptureTestImages.solid(width: 20, height: 10, RGBA(r: 0, g: 255, b: 0, a: 255))

        let tallThumbnail = try XCTUnwrap(RecentCaptureThumbnail.make(from: tall))

        XCTAssertEqual([tallThumbnail.width, tallThumbnail.height], [20, 80])
        XCTAssertTrue(RecentCaptureThumbnail.make(from: tiny) === tiny, "Already small enough")
    }

    /// The thumbnail sits centered on the backing, at half its pixel size in points.
    func testMenuImageCentersTheThumbnailOnTheBacking() throws {
        let red = RGBA(r: 255, g: 0, b: 0, a: 255)
        let thumbnail = try XCTUnwrap(
            RecentCaptureThumbnail.make(from: CaptureTestImages.solid(width: 400, height: 100, red)))
        let image = RecentCaptureThumbnail.menuImage(thumbnail)
        XCTAssertEqual(image.size, RecentCaptureThumbnail.box)

        let rendered = try XCTUnwrap(render(image))

        // 128 x 32 pixels in a 128 x 80 pixel box: rows 24 to 55 from the top.
        XCTAssertTrue(CaptureTestImages.pixel(rendered, x: 64, y: 40).isClose(to: red))
        XCTAssertTrue(CaptureTestImages.pixel(rendered, x: 64, y: 25).isClose(to: red))
        XCTAssertFalse(CaptureTestImages.pixel(rendered, x: 64, y: 22).isClose(to: red, tolerance: 60))
        XCTAssertFalse(CaptureTestImages.pixel(rendered, x: 64, y: 57).isClose(to: red, tolerance: 60))
        let backing = CaptureTestImages.pixel(rendered, x: 64, y: 10)
        XCTAssertGreaterThan(backing.a, 0, "A faint backing fills the box")
        XCTAssertLessThan(backing.a, 64)
        XCTAssertEqual(CaptureTestImages.pixel(rendered, x: 0, y: 0).a, 0, "Its corners are rounded")
    }

    /// `image` drawn at 2x into a transparent sRGB bitmap.
    private func render(_ image: NSImage) -> CGImage? {
        let width = Int(image.size.width * 2), height = Int(image.size.height * 2)
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CaptureTestImages.srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: 2, y: 2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(origin: .zero, size: image.size))
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    // MARK: - Store

    func testRecordPutsASavedCaptureAtTheTopWithItsThumbnail() async throws {
        let folder = try makeFolder()
        let store = store(defaultFolder: folder)
        var changes = 0
        store.onChange = { changes += 1 }
        let file = folder.appendingPathComponent(Self.name(1))

        store.record(result(saving: file))

        XCTAssertEqual(store.captures.map(\.file), [file], "Listed at once, before any scan")
        XCTAssertEqual(changes, 1)
        await settle(store)
        let thumbnail = try XCTUnwrap(store.thumbnail(for: try XCTUnwrap(store.captures.first)))
        XCTAssertEqual([thumbnail.width, thumbnail.height], [128, 64])
        XCTAssertEqual(changes, 2, "The thumbnail updates the menu")
    }

    func testRecordSkipsACaptureThatOnlyWentToTheClipboard() throws {
        let store = store(defaultFolder: try makeFolder())

        store.record(result(saving: nil))

        XCTAssertTrue(store.captures.isEmpty)
    }

    func testRecordKeepsACaptureThatSavedDespiteAProblem() throws {
        let folder = try makeFolder()
        let store = store(defaultFolder: folder)
        let file = folder.appendingPathComponent(Self.name(1))
        let capture = result(saving: nil, copied: false).capture
        let problem = CaptureResult(
            capture: capture,
            png: Data(),
            deliveries: [.file(file, missedFolder: "Shots", annotationDataError: "Disk full")],
            failures: [CaptureSinkFailure(destination: .clipboard, error: CocoaError(.fileWriteUnknown))])
        XCTAssertNotNil(CaptureProblem(problem))

        store.record(problem)

        XCTAssertEqual(store.captures.map(\.file), [file])
    }

    func testScanAndRecordListAFileOnce() async throws {
        let folder = try makeFolder()
        let store = store(defaultFolder: folder)
        let file = try makeFile(Self.name(1), in: folder)
        store.record(result(saving: file))

        store.refresh()
        await settle(store)

        XCTAssertEqual(store.captures.map(\.file), [file])
    }

    func testARescanRemakesTheThumbnailOfAReplacedFile() async throws {
        let folder = try makeFolder()
        let file = try makeFile(Self.name(1), in: folder)
        let store = store(defaultFolder: folder)
        store.refresh()
        await settle(store)
        let first = try XCTUnwrap(store.thumbnail(for: try XCTUnwrap(store.captures.first)))
        XCTAssertEqual([first.width, first.height], [4, 4])

        // Same path and creation date, new contents.
        try makeFile(Self.name(1), in: folder, width: 1000, height: 250)
        store.refresh()
        await settle(store)

        XCTAssertEqual(store.captures.map(\.file), [file])
        let second = try XCTUnwrap(store.thumbnail(for: try XCTUnwrap(store.captures.first)))
        XCTAssertEqual([second.width, second.height], [128, 32])
    }

    func testARecordedThumbnailIsKeptByAScanOfTheSameFile() async throws {
        let folder = try makeFolder()
        let store = store(defaultFolder: folder)
        let scans = HeldScans()
        let file = try makeFile(Self.name(1), in: folder, width: 400, height: 200)
        store.record(result(saving: file))
        await settle(store)
        scans.hold(store)

        store.refresh()
        let scan = try XCTUnwrap(store.scanTask)
        try await waitForHeldScans(scans, count: 1)
        let found = RecentCapture(file: file, createdAt: Self.base, version: FileVersion.of(file))
        scans.land(0, with: RecentCaptureScan(captures: [found]))
        await scan.value

        let thumbnail = try XCTUnwrap(store.thumbnail(for: found), "The file hasn't changed since it was recorded")
        XCTAssertEqual([thumbnail.width, thumbnail.height], [128, 64])
    }

    func testRecordDropsTheThumbnailOfACapturePushedOffTheList() async throws {
        let folder = try makeFolder()
        let store = store(defaultFolder: folder)
        var now = Self.base
        store.now = { now }
        let files = (0...RecentCaptureScanner.limit).map { folder.appendingPathComponent(Self.name($0)) }
        let oldest = RecentCapture(file: files[0], createdAt: Self.base)

        for (index, file) in files.enumerated() {
            now = Self.base.addingTimeInterval(TimeInterval(index))
            store.record(result(saving: file))
            await settle(store)
            if index == 0 { XCTAssertNotNil(store.thumbnail(for: oldest)) }
        }

        XCTAssertEqual(store.captures.count, RecentCaptureScanner.limit)
        XCTAssertFalse(store.captures.contains { $0.file == files[0] })
        XCTAssertNil(store.thumbnail(for: oldest), "Not kept past the limit until the next scan")
    }

    func testRecordKeepsTheListAtEight() throws {
        let folder = try makeFolder()
        let store = store(defaultFolder: folder)
        var now = Self.base
        store.now = { now }

        for index in 0..<10 {
            now = Self.base.addingTimeInterval(TimeInterval(index))
            store.record(result(saving: folder.appendingPathComponent(Self.name(index))))
        }

        XCTAssertEqual(names(store.captures), (2..<10).reversed().map { Self.name($0) })
    }

    func testAScanStartedBeforeALaterOneIsDropped() async throws {
        let folder = try makeFolder()
        let store = store(defaultFolder: folder)
        let scans = HeldScans()
        scans.hold(store)
        let older = RecentCapture(file: folder.appendingPathComponent(Self.name(1)), createdAt: Self.base)
        let newer = RecentCapture(file: folder.appendingPathComponent(Self.name(2)), createdAt: Self.base)

        // One at a time, so the held scans are in the order they started.
        store.refresh()
        let first = try XCTUnwrap(store.scanTask)
        try await waitForHeldScans(scans, count: 1)
        store.refresh()
        let second = try XCTUnwrap(store.scanTask)
        try await waitForHeldScans(scans, count: 2)
        scans.land(1, with: RecentCaptureScan(captures: [newer]))
        await second.value
        scans.land(0, with: RecentCaptureScan(captures: [older], missedFolder: "Shots"))
        await first.value

        XCTAssertEqual(store.captures, [newer])
        XCTAssertNil(store.missedFolder)
    }

    func testACaptureSavedDuringAScanSurvivesIt() async throws {
        let folder = try makeFolder()
        let store = store(defaultFolder: folder)
        let scans = HeldScans()
        scans.hold(store)
        store.now = { Self.base.addingTimeInterval(60) }
        let old = RecentCapture(file: folder.appendingPathComponent(Self.name(1)), createdAt: Self.base)
        let fresh = folder.appendingPathComponent(Self.name(2))

        store.refresh()
        let scan = try XCTUnwrap(store.scanTask)
        try await waitForHeldScans(scans, count: 1)
        store.record(result(saving: fresh))
        scans.land(0, with: RecentCaptureScan(captures: [old]))
        await scan.value

        XCTAssertEqual(store.captures.map(\.file), [fresh, old.file])
    }

    func testACaptureFoundGoneDuringAScanStaysOutWhenItLands() async throws {
        let folder = try makeFolder()
        let store = store(defaultFolder: folder)
        let scans = HeldScans()
        scans.hold(store)
        let gone = RecentCapture(file: folder.appendingPathComponent(Self.name(1)), createdAt: Self.base)
        let kept = RecentCapture(file: folder.appendingPathComponent(Self.name(2)), createdAt: Self.base)

        store.refresh()
        let scan = try XCTUnwrap(store.scanTask)
        try await waitForHeldScans(scans, count: 1)
        store.remove(gone.file)
        // The scan read the folder before the file went.
        scans.land(0, with: RecentCaptureScan(captures: [kept, gone]))
        await scan.value

        XCTAssertEqual(store.captures.map(\.file), [kept.file])
    }

    func testARescanDropsDeletedFilesAndRemoveDropsOneAtOnce() async throws {
        let folder = try makeFolder()
        let store = store(defaultFolder: folder)
        let first = try makeFile(Self.name(1), in: folder, secondsAfterBase: 1)
        let second = try makeFile(Self.name(2), in: folder, secondsAfterBase: 2)
        store.refresh()
        await settle(store)
        XCTAssertEqual(store.captures.map(\.file), [second, first])

        try FileManager.default.removeItem(at: second)
        store.refresh()
        await settle(store)
        XCTAssertEqual(store.captures.map(\.file), [first])

        store.remove(first)
        XCTAssertTrue(store.captures.isEmpty)
    }

    func testClearMenuHidesEverythingUntilNowAndKeepsTheFiles() async throws {
        let folder = try makeFolder()
        let file = try makeFile(Self.name(1), in: folder, secondsAfterBase: 1)
        let store = store(defaultFolder: folder)
        store.refresh()
        await settle(store)
        XCTAssertEqual(store.captures.count, 1)
        store.now = { Self.base.addingTimeInterval(10) }

        store.clear()

        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        store.refresh()
        await settle(store)
        XCTAssertTrue(store.captures.isEmpty, "A later scan stays cleared")

        // Remembered across launches, and a capture made since still appears.
        let later = try makeFile(Self.name(2), in: folder, secondsAfterBase: 20)
        let relaunched = self.store(defaultFolder: folder)
        relaunched.refresh()
        await settle(relaunched)
        XCTAssertEqual(relaunched.captures.map(\.file), [later])
    }

    func testCapturesInAPreviouslyChosenFolderLeaveWhenAnotherIsChosen() async throws {
        let standard = try makeFolder()
        let first = try makeFolder()
        let second = try makeFolder()
        let old = try makeFile(Self.name(1), in: first)
        let folders = CaptureFolderStore(settings: testDefaults.settings)
        try folders.choose(first)
        let store = store(chosen: folders, defaultFolder: standard)
        store.refresh()
        await settle(store)
        XCTAssertEqual(store.captures.map(\.file), [old])

        try folders.choose(second)
        store.refresh()
        await settle(store)

        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
    }

    /// Waits until `scans` holds `count` scans, which arrive from tasks of their own.
    private func waitForHeldScans(_ scans: HeldScans, count: Int) async throws {
        let deadline = Date().addingTimeInterval(5)
        while scans.count < count, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        // Stop the test rather than land the wrong scan and wait on one that never ends.
        guard scans.count == count else {
            throw CocoaError(.userCancelled, userInfo: [NSDebugDescriptionErrorKey: "Expected \(count) held scans, have \(scans.count)"])
        }
    }

    // MARK: - File actions

    private func privatePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RecentCapturesTests-\(UUID().uuidString)"))
        addTeardownBlock { @MainActor in pasteboard.releaseGlobally() }
        return pasteboard
    }

    func testCopyPutsTheFilesBytesOnThePasteboard() async throws {
        let file = try makeFile(Self.name(1), in: try makeFolder())
        var actions = CaptureFileActions()
        actions.pasteboard = privatePasteboard()

        let outcome = await actions.copy(file, from: CaptureFolderStore(settings: testDefaults.settings))

        guard case .copied = outcome else { return XCTFail("Expected a copy, got \(outcome)") }
        XCTAssertEqual(actions.pasteboard.data(forType: .png), try Data(contentsOf: file))
    }

    func testCopyOfAVanishedFileIsMissing() async throws {
        let file = try makeFolder().appendingPathComponent(Self.name(1))
        var actions = CaptureFileActions()
        actions.pasteboard = privatePasteboard()

        let outcome = await actions.copy(file, from: CaptureFolderStore(settings: testDefaults.settings))

        guard case .missing = outcome else { return XCTFail("Expected missing, got \(outcome)") }
        XCTAssertNil(actions.pasteboard.data(forType: .png))
    }

    func testReadTellsAFailedReadFromAFileThatIsGone() throws {
        let file = URL(fileURLWithPath: "/Captures/\(Self.name(1))")
        let failing: (URL) throws -> Data = { _ in throw CocoaError(.fileReadNoPermission) }

        guard case .failed(let error) = CaptureFileActions.read(file, fileExists: { _ in true }, readFile: failing) else {
            return XCTFail("A file that is there but can't be read is a failure")
        }
        XCTAssertEqual((error as? CocoaError)?.code, .fileReadNoPermission)

        // Gone between the check and the read.
        var checks = 0
        let goneDuringRead = CaptureFileActions.read(
            file,
            fileExists: { _ in
                checks += 1
                return checks == 1
            },
            readFile: failing)
        guard case .missing = goneDuringRead else { return XCTFail("Expected missing, got \(goneDuringRead)") }

        var reads = 0
        let gone = CaptureFileActions.read(
            file,
            fileExists: { _ in false },
            readFile: { _ in
                reads += 1
                return Data()
            })
        guard case .missing = gone else { return XCTFail("Expected missing, got \(gone)") }
        XCTAssertEqual(reads, 0)

        guard case .read(let data) = CaptureFileActions.read(file, fileExists: { _ in true }, readFile: { _ in Data([7]) })
        else { return XCTFail("Expected the bytes") }
        XCTAssertEqual(data, Data([7]))
    }

    func testCopyThatCantReadTheFileFails() async throws {
        let file = try makeFile(Self.name(1), in: try makeFolder())
        var actions = CaptureFileActions()
        actions.pasteboard = privatePasteboard()
        actions.readFile = { _ in throw CocoaError(.fileReadNoPermission) }

        let outcome = await actions.copy(file, from: CaptureFolderStore(settings: testDefaults.settings))

        guard case .failed(let error) = outcome else { return XCTFail("Expected a failure, got \(outcome)") }
        XCTAssertEqual((error as? CocoaError)?.code, .fileReadNoPermission)
        XCTAssertNil(actions.pasteboard.data(forType: .png))
    }

    func testPrepareFolderCreatesAMissingFolder() throws {
        let folder = try makeFolder().appendingPathComponent("New/Captures", isDirectory: true)

        guard case .success(let prepared) = CaptureFileActions.prepareFolder(folder) else {
            return XCTFail("Expected the folder to be created")
        }

        XCTAssertEqual(prepared, folder)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
