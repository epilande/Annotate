import XCTest
import SwiftUI

@testable import Annotate

/// Records notices instead of sending them: the real notification center raises an exception
/// outside an app bundle, and must never send anything from a test.
@MainActor
final class StubCaptureNotifier: CaptureNotifying {
    var currentAccess: CaptureNotificationAccess = .allowed
    private(set) var notices: [CaptureNotice] = []

    func access() async -> CaptureNotificationAccess { currentAccess }
    func requestAccess() async -> CaptureNotificationAccess { currentAccess }
    func post(_ notice: CaptureNotice) { notices.append(notice) }
}

@MainActor
final class CaptureDestinationsTests: XCTestCase {
    private static let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
    private static let date = Date(timeIntervalSince1970: 0)

    private var testDefaults: UserDefaults!
    private var folders: CaptureFolderStore!

    override func setUp() {
        super.setUp()
        testDefaults = TestUserDefaults.create()
        folders = CaptureFolderStore(settings: testDefaults.settings)
    }

    override func tearDown() {
        TestUserDefaults.removeSuite()
        testDefaults = nil
        folders = nil
        super.tearDown()
    }

    /// A new folder that is removed after the test.
    private func makeFolder(_ name: String = UUID().uuidString) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnnotateCaptureDestinationsTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// `url`'s path with `/private` and other links gone: bookmarks resolve to the real path,
    /// and the temporary folder isn't one.
    private func real(_ url: URL?) -> String? {
        url?.resolvingSymlinksInPath().path
    }

    private func parent(_ url: URL?) -> String? {
        real(url?.deletingLastPathComponent())
    }

    private func chosenPath(_ state: CaptureFolderState) -> String? {
        if case .chosen(let folder) = state { return real(folder) }
        return nil
    }

    private func missingFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnnotateCaptureDestinationsTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func files(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
    }

    private func capture() -> Capture {
        Capture(
            image: CaptureTestImages.solid(width: 40, height: 20, Self.blue),
            display: DisplayInfo(id: 7, frame: CGRect(x: 0, y: 0, width: 20, height: 10), scale: 2),
            region: CGRect(x: 0, y: 0, width: 20, height: 10),
            scene: nil,
            capturedAt: Self.date,
            hostTime: 0)
    }

    private func result(
        _ deliveries: [CaptureDelivery], failures: [CaptureSinkFailure] = []
    ) -> CaptureResult {
        CaptureResult(capture: capture(), deliveries: deliveries, failures: failures)
    }

    private func deliver(with sink: FileSink) async throws -> (url: URL, missedFolder: String?) {
        let delivery = try await sink.deliver(capture(), png: Data([1, 2, 3]))
        guard case let .file(url, missedFolder) = delivery else {
            XCTFail("Expected a file, got \(delivery)")
            throw CaptureError.renderFailed
        }
        return (url, missedFolder)
    }

    private func request(_ afterCapture: AfterCapture) -> CaptureRequest {
        CaptureRequest(
            display: DisplayInfo(id: 7, frame: CGRect(x: 0, y: 0, width: 40, height: 20), scale: 1),
            scene: nil,
            hostTime: 0,
            date: Self.date,
            afterCapture: afterCapture)
    }

    // MARK: - Entitlements

    func testEntitlementsAllowWritingToAChosenFolderAcrossLaunches() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let file = repository.appendingPathComponent("Annotate/Annotate.entitlements")
        try XCTSkipUnless(FileManager.default.isReadableFile(atPath: file.path), "The sandboxed Xcode host can't read it")
        let entitlements = try XCTUnwrap(NSDictionary(contentsOf: file))

        XCTAssertEqual(entitlements["com.apple.security.files.user-selected.read-write"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.files.bookmarks.app-scope"] as? Bool, true)
        XCTAssertNil(
            entitlements["com.apple.security.files.user-selected.read-only"],
            "With both, which one wins isn't documented")
        XCTAssertEqual(entitlements["com.apple.security.assets.pictures.read-write"] as? Bool, true)
    }

    // MARK: - Chosen folder

    func testChosenFolderRoundTripsThroughItsBookmark() async throws {
        let chosen = try makeFolder("Shots")
        let standard = missingFolder()
        try folders.choose(chosen)

        // A new store reads the bookmark back, as the next launch does.
        let reloaded = CaptureFolderStore(settings: testDefaults.settings)
        XCTAssertEqual(chosenPath(reloaded.state), real(chosen))

        let saved = try await deliver(with: FileSink(folder: standard, chosenFolder: reloaded))

        XCTAssertEqual(parent(saved.url), real(chosen))
        XCTAssertNil(saved.missedFolder)
        XCTAssertEqual(try Data(contentsOf: saved.url), Data([1, 2, 3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: standard.path), "The default folder stays out of it")
    }

    func testNoChosenFolderSavesToTheDefault() async throws {
        let standard = try makeFolder()
        XCTAssertEqual(folders.state, .standard)

        let saved = try await deliver(with: FileSink(folder: standard, chosenFolder: folders))

        XCTAssertEqual(parent(saved.url), real(standard))
        XCTAssertNil(saved.missedFolder)
    }

    func testUseDefaultFolderForgetsTheBookmark() throws {
        try folders.choose(try makeFolder())

        folders.useDefaultFolder()

        XCTAssertNil(folders.bookmark)
        XCTAssertEqual(folders.state, .standard)
        XCTAssertFalse(testDefaults.settings.hasValue(for: .captureFolderBookmark))
    }

    func testDeletedFolderFallsBackToTheDefaultAndNamesWhatItMissed() async throws {
        let chosen = try makeFolder("Client Shots")
        let standard = try makeFolder()
        try folders.choose(chosen)
        try FileManager.default.removeItem(at: chosen)

        guard case .unreachable(let path) = folders.state else { return XCTFail("\(folders.state)") }
        XCTAssertEqual(path.map { URL(fileURLWithPath: $0).lastPathComponent }, "Client Shots")
        let saved = try await deliver(with: FileSink(folder: standard, chosenFolder: folders))

        XCTAssertEqual(parent(saved.url), real(standard))
        XCTAssertEqual(saved.missedFolder, "Client Shots")
        XCTAssertFalse(FileManager.default.fileExists(atPath: chosen.path), "A missing folder is not recreated")
        XCTAssertNotNil(folders.bookmark, "It may come back, as an unplugged drive does")
    }

    func testUnreadableBookmarkFallsBackToTheDefault() async throws {
        let standard = try makeFolder()
        testDefaults.settings[.captureFolderBookmark] = Data("not a bookmark".utf8)

        XCTAssertEqual(folders.state, .unreachable(path: nil))
        let saved = try await deliver(with: FileSink(folder: standard, chosenFolder: folders))

        XCTAssertEqual(parent(saved.url), real(standard))
        XCTAssertEqual(saved.missedFolder, "Your Folder")
    }

    func testFolderInTheTrashCountsAsGone() throws {
        let home = URL(fileURLWithPath: "/Users/me/.Trash/Shots")
        let volume = URL(fileURLWithPath: "/Volumes/Disk/.Trashes/501/Shots")
        XCTAssertTrue(CaptureFolderBookmark.isInTrash(home))
        XCTAssertTrue(CaptureFolderBookmark.isInTrash(volume))
        XCTAssertFalse(CaptureFolderBookmark.isInTrash(URL(fileURLWithPath: "/Users/me/Trash/Shots")))

        let parent = try makeFolder()
        let trashed = parent.appendingPathComponent(".Trash/Shots", isDirectory: true)
        try FileManager.default.createDirectory(at: trashed, withIntermediateDirectories: true)
        XCTAssertNil(CaptureFolderBookmark.resolve(try CaptureFolderBookmark.make(for: trashed)))
    }

    func testMovedFolderIsFollowedAndItsStaleBookmarkRenewed() async throws {
        let chosen = try makeFolder("Before")
        let moved = chosen.deletingLastPathComponent().appendingPathComponent("After", isDirectory: true)
        try folders.choose(chosen)
        let original = try XCTUnwrap(folders.bookmark)
        try FileManager.default.moveItem(at: chosen, to: moved)
        let resolved = try XCTUnwrap(CaptureFolderBookmark.resolve(original))
        try XCTSkipUnless(resolved.isStale, "macOS didn't call this bookmark stale")

        let saved = try await deliver(with: FileSink(folder: missingFolder(), chosenFolder: folders))

        XCTAssertEqual(parent(saved.url), real(moved))
        XCTAssertNil(saved.missedFolder)
        let renewed = try XCTUnwrap(folders.bookmark)
        XCTAssertNotEqual(renewed, original)
        XCTAssertEqual(CaptureFolderBookmark.resolve(renewed)?.isStale, false)
    }

    func testRenewingNeverReplacesAFolderChosenMeanwhile() throws {
        try folders.choose(try makeFolder())
        let stale = try XCTUnwrap(folders.bookmark)
        try folders.choose(try makeFolder())
        let current = try XCTUnwrap(folders.bookmark)

        folders.renew(stale, with: Data([9]))
        XCTAssertEqual(folders.bookmark, current)

        folders.renew(current, with: Data([9]))
        XCTAssertEqual(folders.bookmark, Data([9]))
    }

    func testFailedWriteToTheChosenFolderFallsBackToTheDefault() async throws {
        let chosen = try makeFolder("Read Only")
        let standard = try makeFolder()
        try folders.choose(chosen)
        var sink = FileSink(folder: standard, chosenFolder: folders)
        let chosenName = chosen.lastPathComponent
        sink.writeBytes = { data, url in
            if url.deletingLastPathComponent().lastPathComponent == chosenName {
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileSink.writeWithoutOverwriting(data, url)
        }

        let saved = try await deliver(with: sink)

        XCTAssertEqual(parent(saved.url), real(standard))
        XCTAssertEqual(saved.missedFolder, "Read Only")
        XCTAssertEqual(try files(in: chosen), [], "Not even a temporary file")
    }

    func testFailureInBothFoldersThrows() async throws {
        let standard = try makeFolder()
        try folders.choose(try makeFolder())
        var sink = FileSink(folder: standard, chosenFolder: folders)
        sink.writeBytes = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }

        do {
            _ = try await sink.deliver(capture(), png: Data([1]))
            XCTFail("Expected the save to fail")
        } catch {
            XCTAssertEqual((error as? CocoaError)?.code, .fileWriteOutOfSpace)
        }
    }

    func testCaptureSinksReadTheChosenFolderForEachCapture() async throws {
        let standard = try makeFolder()
        let chosen = try makeFolder()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CaptureDestinationsTests-\(UUID().uuidString)"))
        addTeardownBlock { @MainActor in pasteboard.releaseGlobally() }
        let service = CaptureService(
            source: StubDisplayCapturing(snapshotImage: CaptureTestImages.solid(width: 40, height: 20, Self.blue)),
            sinks: AppDelegate.captureSinks(
                folder: standard, chosenFolder: folders, pasteboard: pasteboard, arguments: ["Annotate"]))

        let before = try await service.capture(request(.both))
        try folders.choose(chosen)
        let after = try await service.capture(request(.both))

        XCTAssertEqual(parent(before.savedFile), real(standard))
        XCTAssertEqual(parent(after.savedFile), real(chosen))
    }

    // MARK: - After Capture

    func testAfterCaptureRawValuesAreTheStoredContract() {
        XCTAssertEqual(AfterCapture.allCases.map(\.rawValue), ["save", "copy", "both"])
        XCTAssertEqual(
            AfterCapture.allCases.map(\.title), ["Save to folder", "Copy to clipboard", "Both"])
    }

    func testServiceDeliversOnlyWhereAfterCaptureSays() async throws {
        let cases: [(AfterCapture, savesFile: Bool, copies: Bool)] = [
            (.save, true, false),
            (.copy, false, true),
            (.both, true, true),
        ]
        for (afterCapture, savesFile, copies) in cases {
            let folder = try makeFolder()
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("CaptureDestinationsTests-\(UUID().uuidString)"))
            addTeardownBlock { @MainActor in pasteboard.releaseGlobally() }
            let service = CaptureService(
                source: StubDisplayCapturing(snapshotImage: CaptureTestImages.solid(width: 40, height: 20, Self.blue)),
                sinks: [FileSink(folder: folder), ClipboardSink(pasteboard: pasteboard)])

            let result = try await service.capture(request(afterCapture))

            XCTAssertEqual(result.savedFile != nil, savesFile, "\(afterCapture)")
            XCTAssertEqual(try files(in: folder).count, savesFile ? 1 : 0, "\(afterCapture)")
            XCTAssertEqual(result.copiedToClipboard, copies, "\(afterCapture)")
            XCTAssertEqual(pasteboard.data(forType: .png) != nil, copies, "\(afterCapture)")
            XCTAssertTrue(result.failures.isEmpty, "\(afterCapture)")
        }
    }

    func testSinkLeftOutByAfterCaptureCantFailTheCapture() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CaptureDestinationsTests-\(UUID().uuidString)"))
        addTeardownBlock { @MainActor in pasteboard.releaseGlobally() }
        let service = CaptureService(
            source: StubDisplayCapturing(snapshotImage: CaptureTestImages.solid(width: 40, height: 20, Self.blue)),
            sinks: [FailingSink(destination: .file), ClipboardSink(pasteboard: pasteboard)])

        let result = try await service.capture(request(.copy))

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertNil(CaptureProblem(result))
    }

    // MARK: - Problems

    func testProblemIsNilForEverythingThatWentAsAsked() {
        let file = URL(fileURLWithPath: "/tmp/Shot.png")
        XCTAssertNil(CaptureProblem(result([.file(file), .clipboard])))
        XCTAssertNil(CaptureProblem(result([.file(file)])))
        XCTAssertNil(CaptureProblem(result([.clipboard])), "Copy to clipboard saves no file on purpose")
    }

    func testProblemSaysWhichDestinationFailed() {
        let file = URL(fileURLWithPath: "/tmp/Shot.png")
        let failure = CocoaError(.fileWriteUnknown)

        XCTAssertEqual(
            CaptureProblem(result([.clipboard], failures: [CaptureSinkFailure(destination: .file, error: failure)])),
            .saveFailed(error: failure))
        XCTAssertEqual(
            CaptureProblem(result([.file(file)], failures: [CaptureSinkFailure(destination: .clipboard, error: failure)])),
            .copyFailed(savedAs: file, error: failure))
    }

    func testProblemNamesAFolderThatWasMissed() throws {
        let file = FileSink.defaultFolder.appendingPathComponent("Shot.png")

        let problem = try XCTUnwrap(CaptureProblem(result([.file(file, missedFolder: "Client Shots"), .clipboard])))

        XCTAssertEqual(problem.title, "Can't Reach Client Shots. Saved to Default Folder")
        XCTAssertTrue(problem.detail.contains("Shot.png"), problem.detail)
        XCTAssertTrue(problem.detail.contains("~/Pictures/Annotate"), problem.detail)
    }

    // MARK: - Notifications

    func testNoticeForASavedCaptureCarriesTheFile() throws {
        let file = URL(fileURLWithPath: "/tmp/Shot.png")

        let notice = try XCTUnwrap(CaptureNotice(result([.file(file), .clipboard])))

        XCTAssertEqual(notice.title, "Capture Saved")
        XCTAssertEqual(notice.body, "Shot.png")
        XCTAssertEqual(notice.file, file)
    }

    func testNoticeForAClipboardOnlyCaptureHasNoFile() throws {
        let notice = try XCTUnwrap(CaptureNotice(result([.clipboard])))

        XCTAssertEqual(notice.title, "Capture Copied")
        XCTAssertNil(notice.file)
    }

    func testNoticeSaysWhenTheFileWentToTheDefaultFolder() throws {
        let file = URL(fileURLWithPath: "/tmp/Shot.png")

        let notice = try XCTUnwrap(CaptureNotice(result([.file(file, missedFolder: "Client Shots")])))

        XCTAssertEqual(notice.title, "Capture Saved to the Default Folder")
    }

    func testNoNoticeWithoutADelivery() {
        XCTAssertNil(CaptureNotice(result([])))
    }

    func testResponseShowsTheFileFromTheButtonAndFromAClickOnTheNotification() {
        let file = URL(fileURLWithPath: "/tmp/Annotate 2026-11-05 at 10.00.00.png")
        let userInfo = CaptureNotice.userInfo(for: file)

        XCTAssertEqual(
            CaptureNotice.fileToShow(action: CaptureNotice.showInFinderAction, userInfo: userInfo), file)
        XCTAssertEqual(
            CaptureNotice.fileToShow(action: "com.apple.UNNotificationDefaultActionIdentifier", userInfo: userInfo), file)
    }

    func testResponseShowsNothingWhenDismissedOrWithoutAFile() {
        let userInfo = CaptureNotice.userInfo(for: URL(fileURLWithPath: "/tmp/Shot.png"))

        XCTAssertNil(CaptureNotice.fileToShow(action: "com.apple.UNNotificationDismissActionIdentifier", userInfo: userInfo))
        XCTAssertNil(
            CaptureNotice.fileToShow(
                action: CaptureNotice.showInFinderAction, userInfo: CaptureNotice.userInfo(for: nil)))
    }

    func testThumbnailIsItsOwnFileNoLargerThanTheLimit() throws {
        let folder = try makeFolder()
        let image = CaptureTestImages.solid(width: 2000, height: 1000, Self.blue)

        let thumbnail = try XCTUnwrap(CaptureNotice.writeThumbnail(of: image, maxPixels: 100, in: folder))

        XCTAssertEqual(thumbnail.pathExtension, "png")
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: thumbnail)))
        XCTAssertEqual(decoded.pixelsWide, 100)
        XCTAssertEqual(decoded.pixelsHigh, 50)
        XCTAssertTrue(
            CaptureTestImages.pixel(try XCTUnwrap(decoded.cgImage), x: 50, y: 25).isClose(to: Self.blue))
    }

    func testThumbnailNeverScalesASmallImageUp() throws {
        let folder = try makeFolder()
        let image = CaptureTestImages.solid(width: 40, height: 20, Self.blue)

        let thumbnail = try XCTUnwrap(CaptureNotice.writeThumbnail(of: image, in: folder))

        let decoded = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: thumbnail)))
        XCTAssertEqual(decoded.pixelsWide, 40)
        XCTAssertEqual(decoded.pixelsHigh, 20)
    }

    func testSwiftPMTestProcessGetsTheSilentNotifier() throws {
        try XCTSkipIf(Bundle.main.bundleURL.pathExtension == "app", "Xcode hosts tests inside Annotate.app")

        XCTAssertTrue(SystemCaptureNotifier.forThisProcess(folders: folders) is SilentCaptureNotifier)
    }

    // MARK: - Capture pane

    func testPaneShowsTheFolderForEachState() {
        let home = FileSink.realHomeDirectory
        XCTAssertEqual(CaptureSettingsView.displayPath(of: .standard), "~/Pictures/Annotate")
        XCTAssertEqual(
            CaptureSettingsView.displayPath(of: .chosen(home.appendingPathComponent("Shots"))), "~/Shots")
        XCTAssertEqual(
            CaptureSettingsView.displayPath(of: .chosen(URL(fileURLWithPath: "/Volumes/Disk/Shots"))),
            "/Volumes/Disk/Shots")
        XCTAssertEqual(CaptureSettingsView.displayPath(of: .unreachable(path: "/Volumes/Disk/Shots")), "/Volumes/Disk/Shots")
        XCTAssertEqual(CaptureSettingsView.displayPath(of: .unreachable(path: nil)), "Unknown folder")
    }

    func testPaneSummaryFollowsAfterCapture() {
        XCTAssertTrue(CaptureSettingsView.captureSummary(.save).hasSuffix("It is saved to this folder."))
        XCTAssertTrue(CaptureSettingsView.captureSummary(.copy).contains("no file is saved"))
        XCTAssertTrue(
            CaptureSettingsView.captureSummary(.both).hasSuffix("saved to this folder and copied to the clipboard."))
    }

    func testPaneEmbedsWithAChosenFolderAndAStubNotifier() throws {
        try folders.choose(try makeFolder())
        let view = CaptureSettingsView(folders: folders, notifier: StubCaptureNotifier())

        let host = NSHostingController(rootView: view)

        XCTAssertNotNil(host.view)
    }
}
