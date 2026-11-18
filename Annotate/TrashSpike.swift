#if DEBUG || TRASH_SPIKE
import AppKit
import os
import Security

private let log = Logger(subsystem: "com.epilande.Annotate", category: "TrashSpike")

/// Throwaway spike, not for merge: what Move to Trash can do on captures in the sandbox.
///
/// Every case writes its own fixture pair (`Annotate Trash Spike … .png` plus its `.json`)
/// and trashes only that, so real captures are never touched. The chosen folder's bookmark
/// lives in a file in the app's container, never in `.captureFolderBookmark`, so the user's
/// chosen capture folder stays as it is.
///
/// Status menu: Trash Spike. Headless: launch with `--trash-spike default` or
/// `--trash-spike bookmark`; the report goes to stdout and the process exits.
@MainActor
enum TrashSpike {
    static let launchArgument = "--trash-spike"

    /// Every item a case trashed this run, keyed by API, for the Put Back evidence section.
    private static var trashed: [(api: String, url: URL)] = []

    // MARK: Entry points

    static func makeMenuItem() -> NSMenuItem {
        let submenu = NSMenu(title: "Trash Spike")
        submenu.addItem(item("Default Folder: Run Cases", #selector(TrashSpikeTarget.runDefault)))
        submenu.addItem(item("Chosen Folder: Choose and Run…", #selector(TrashSpikeTarget.chooseAndRun)))
        submenu.addItem(
            item("Chosen Folder: Run From Saved Bookmark", #selector(TrashSpikeTarget.runFromBookmark)))
        submenu.addItem(item("Chosen Folder: Forget Saved Bookmark", #selector(TrashSpikeTarget.forget)))
        let item = NSMenuItem(title: "Trash Spike", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private static func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = TrashSpikeTarget.shared
        return item
    }

    /// Runs the case named after `launchArgument`, prints the report, and exits. Returns false
    /// when the argument isn't there.
    static func runFromLaunchArguments() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: launchArgument) else { return false }
        let mode = arguments.indices.contains(index + 1) ? arguments[index + 1] : "default"
        Task { @MainActor in
            let report: String
            switch mode {
            case "adopt": return  // waits for a folder from `adoptOpenedFolder`
            case "bookmark": report = await runChosenFromBookmark()
            default: report = await runDefaultFolder()
            }
            print(report)
            fflush(stdout)
            exit(0)
        }
        return true
    }

    // MARK: Runs

    static func runDefaultFolder() async -> String {
        var report = header("Default folder")
        let folder = FileSink.defaultFolder
        report.line("folder: \(folder.path)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            report.line("createDirectory FAILED: \(describe(error))")
        }
        await runAllCases(in: folder, label: "default", into: &report)
        return report.text
    }

    /// Asks for a folder, saves its bookmark, runs every case through the panel's grant, then
    /// leaves one fixture pair behind for the relaunch leg to trash.
    static func chooseAndRun() async -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder OUTSIDE ~/Pictures, e.g. ~/Desktop/Annotate Trash Spike"
        guard await panel.begin() == .OK, let folder = panel.url else { return nil }
        return await runChosen(folder, grantedBy: "the open panel")
    }

    /// Takes a folder opened through Launch Services (`open -a Annotate.app <folder>`), which
    /// grants it the way a drop on the app does. Lets the chosen-folder leg run without the
    /// open panel's UI. Returns false when `urls` holds no folder.
    static func adoptOpenedFolder(_ urls: [URL]) -> Bool {
        guard CommandLine.arguments.contains(launchArgument),
              let folder = urls.first(where: { $0.isFileURL && $0.hasDirectoryPath })
        else { return false }
        Task { @MainActor in
            print(await runChosen(folder, grantedBy: "Launch Services (open -a)"))
            fflush(stdout)
            exit(0)
        }
        return true
    }

    /// Saves `folder`'s bookmark, runs every case through the grant it came with, then leaves
    /// one fixture pair behind for the relaunch leg to trash.
    private static func runChosen(_ folder: URL, grantedBy grant: String) async -> String {
        var report = header("Chosen folder, same launch as the grant from \(grant)")
        report.line("folder: \(folder.path)")
        if folder.path.hasPrefix(FileSink.realHomeDirectory.appendingPathComponent("Pictures").path) {
            report.line("WARNING: folder is under ~/Pictures, so the Pictures entitlement masks the bookmark result")
        }
        do {
            let bookmark = try CaptureFolderBookmark.make(for: folder)
            try bookmark.write(to: bookmarkFile, options: .atomic)
            report.line("bookmark saved: \(bookmark.count) bytes at \(bookmarkFile.path)")
        } catch {
            report.line("bookmark save FAILED: \(describe(error))")
        }
        await runAllCases(in: folder, label: "chosen-grant", into: &report)
        report.line("")
        report.line("Leftover pairs for the relaunch leg:")
        for label in ["leftover-trashItem", "leftover-recycle"] {
            if let (png, json) = makeFixture(in: folder, label: label, into: &report) {
                report.line("  \(png.lastPathComponent)")
                report.line("  \(json.lastPathComponent)")
            }
        }
        report.line("")
        report.line("Next: quit Annotate (status menu > Quit), relaunch it, run Chosen Folder: Run From Saved Bookmark.")
        return report.text
    }

    /// The relaunch leg. Uses only the saved bookmark, never a panel.
    static func runChosenFromBookmark() async -> String {
        var report = header("Chosen folder, from saved bookmark (no open panel this launch)")
        guard let data = try? Data(contentsOf: bookmarkFile) else {
            report.line("no saved bookmark at \(bookmarkFile.path). Run Chosen Folder: Choose and Run… first.")
            return report.text
        }
        report.line("bookmark: \(data.count) bytes")
        report.line("bookmark path (no resolve): \(CaptureFolderBookmark.path(of: data) ?? "nil")")
        guard let resolved = CaptureFolderBookmark.resolve(data) else {
            report.line("CaptureFolderBookmark.resolve returned nil (gone, in Trash, or unmounted)")
            return report.text
        }
        let folder = resolved.url
        report.line("resolved: \(folder.path) isStale=\(resolved.isStale)")

        // Negative control: before this launch starts the scope, the app shouldn't reach the
        // folder at all. Uses a plain path URL, not the resolved one.
        let plain = URL(fileURLWithPath: folder.path, isDirectory: true)
        report.line("")
        report.line("[control, no scope] list folder by path: \(probeList(plain))")
        report.line("[control, no scope] write file by path: \(probeWrite(in: plain))")

        let isAccessing = folder.startAccessingSecurityScopedResource()
        report.line("")
        report.line("startAccessingSecurityScopedResource() = \(isAccessing)")
        report.line("[scoped] list folder: \(probeList(folder))")
        let leftovers = leftoverFixtures(in: folder)
        report.line("[scoped] leftover fixtures from the earlier launch: \(leftovers.count == 0 ? "none found" : "\(leftovers.count)")")

        // The real PR 3 situation: a capture saved in an earlier launch.
        let pngs = leftovers.filter { $0.pathExtension == "png" }.sorted { $0.path < $1.path }
        for png in pngs {
            let json = FileSink.recordURL(for: png)
            report.line("")
            if png.lastPathComponent.contains("leftover-recycle") {
                report.line("Case leftover (saved in an earlier launch): NSWorkspace.recycle [png, json]")
                report.line("  pair: " + (await recycle([png, json])))
            } else {
                report.line("Case leftover (saved in an earlier launch): FileManager.trashItem")
                report.line("  png:  " + trashItem(png))
                report.line("  json: " + trashItem(json))
            }
        }

        // Control: does Trash itself need the scope, or only the fixture write? The pair is
        // made under the scope, then the scope is stopped before trashing.
        report.line("")
        report.line("Case control: scope STOPPED before trashing (expect ERR if the scope is what grants it)")
        if let (png, json) = makeFixture(in: folder, label: "unscoped", into: &report) {
            if isAccessing { folder.stopAccessingSecurityScopedResource() }
            report.line("  png  trashItem: " + trashItem(png))
            report.line("  json recycle:   " + (await recycle([json])))
            if isAccessing { _ = folder.startAccessingSecurityScopedResource() }
            for url in [png, json] where FileManager.default.fileExists(atPath: url.path) {
                report.line("  cleanup with scope: " + trashItem(url))
            }
        }

        // A plain-path URL after the scope is started: does the grant follow the path, or only
        // the resolved URL instance?
        report.line("")
        report.line("Case plain-path URL while the resolved URL holds the scope: FileManager.trashItem")
        if let (png, json) = makeFixture(in: folder, label: "plainpath", into: &report) {
            let plainPNG = URL(fileURLWithPath: png.path)
            let plainJSON = URL(fileURLWithPath: json.path)
            report.line("  png:  " + trashItem(plainPNG))
            report.line("  json: " + trashItem(plainJSON))
        }

        await runAllCases(in: folder, label: "chosen-bookmark", into: &report)

        if isAccessing { folder.stopAccessingSecurityScopedResource() }

        // After the scope is stopped, the folder should be out of reach again.
        report.line("")
        report.line("[after stop] write file by path: \(probeWrite(in: plain))")
        return report.text
    }

    // MARK: Cases

    /// The same four cases for any folder. The caller holds whatever access it needs; recycle
    /// is awaited, so a scope held by the caller covers its completion.
    private static func runAllCases(in folder: URL, label: String, into report: inout Report) async {
        report.line("")
        report.line("Case 1: FileManager.trashItem, png then json (two calls)")
        if let (png, json) = makeFixture(in: folder, label: "\(label)-trashItem", into: &report) {
            report.line("  png:  " + trashItem(png))
            report.line("  json: " + trashItem(json))
        }

        report.line("")
        report.line("Case 2: NSWorkspace.recycle, png alone then json alone")
        if let (png, json) = makeFixture(in: folder, label: "\(label)-recycle-each", into: &report) {
            report.line("  png:  " + (await recycle([png])))
            report.line("  json: " + (await recycle([json])))
        }

        report.line("")
        report.line("Case 3: NSWorkspace.recycle, [png, json] in one call")
        if let (png, json) = makeFixture(in: folder, label: "\(label)-recycle-pair", into: &report) {
            report.line("  pair: " + (await recycle([png, json])))
        }

        report.line("")
        report.line("Case 4: FileManager.trashItem on png, json left alone (orphan check)")
        if let (png, json) = makeFixture(in: folder, label: "\(label)-orphan", into: &report) {
            report.line("  png:  " + trashItem(png))
            report.line("  json still there: \(FileManager.default.fileExists(atPath: json.path))")
            report.line("  json: " + trashItem(json))
        }
        await putBackEvidence(into: &report)
    }

    /// What macOS kept for Put Back. Finder records it in the Trash's `.DS_Store` as a `ptbL`
    /// (original folder) and `ptbN` (original name) entry per item. Finder writes that file a
    /// little later, so this waits first. The Finder check in the live steps is the verdict.
    private static func putBackEvidence(into report: inout Report) async {
        try? await Task.sleep(for: .seconds(3))
        report.line("")
        report.line("Put Back evidence (Finder > Trash > right-click > Put Back is the verdict)")
        let store = FileSink.realHomeDirectory.appendingPathComponent(".Trash/.DS_Store")
        let storeData: Data?
        do {
            storeData = try Data(contentsOf: store)
            report.line("  ~/.Trash/.DS_Store readable: \(storeData?.count ?? 0) bytes")
        } catch {
            storeData = nil
            report.line("  ~/.Trash/.DS_Store: ERR \(describe(error))")
        }
        for item in trashed {
            let name = item.url.lastPathComponent
            var line = "  [\(item.api)] \(name): xattrs=\(xattrs(item.url))"
            if let storeData {
                line += " ptbL=\(hasRecord(storeData, name: name, code: "ptbL")) ptbN=\(hasRecord(storeData, name: name, code: "ptbN"))"
            }
            report.line(line)
        }
        trashed.removeAll()
    }

    private static func hasRecord(_ store: Data, name: String, code: String) -> Bool {
        var needle = Data()
        let units = Array(name.utf16)
        withUnsafeBytes(of: UInt32(units.count).bigEndian) { needle.append(contentsOf: $0) }
        for unit in units { withUnsafeBytes(of: unit.bigEndian) { needle.append(contentsOf: $0) } }
        needle.append(Data(code.utf8))
        return store.range(of: needle) != nil
    }

    private static func xattrs(_ url: URL) -> String {
        let size = listxattr(url.path, nil, 0, 0)
        guard size > 0 else { return size == 0 ? "none" : "ERR errno \(errno)" }
        var buffer = [CChar](repeating: 0, count: size)
        listxattr(url.path, &buffer, size, 0)
        let names = buffer.split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        return names.joined(separator: ",")
    }

    private static func trashItem(_ url: URL) -> String {
        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            if let resulting { trashed.append(("trashItem", resulting as URL)) }
            return "OK  → \(resulting?.path ?? "nil")  \(afterState(url, trashed: resulting as URL?))"
        } catch {
            return "ERR \(describe(error))  \(afterState(url, trashed: nil))"
        }
    }

    private static func recycle(_ urls: [URL]) async -> String {
        do {
            let moved = try await NSWorkspace.shared.recycle(urls)
            trashed += moved.values.map { ("recycle", $0) }
            let parts = urls.map { url in
                let destination = moved[url]
                return "\(url.lastPathComponent) → \(destination?.path ?? "nil")  \(afterState(url, trashed: destination))"
            }
            return "OK  " + parts.joined(separator: " | ")
        } catch {
            let states = urls.map { "\($0.lastPathComponent): \(afterState($0, trashed: nil))" }
            return "ERR \(describe(error))  " + states.joined(separator: " | ")
        }
    }

    /// No error is no proof: whether the source is really gone and whether the app can see the
    /// trashed copy.
    private static func afterState(_ source: URL, trashed: URL?) -> String {
        let fileManager = FileManager.default
        var state = "[source exists: \(fileManager.fileExists(atPath: source.path))"
        if let trashed {
            state += ", trashed copy visible to app: \(fileManager.fileExists(atPath: trashed.path))"
        }
        return state + "]"
    }

    // MARK: Fixtures

    private static let fixturePrefix = "Annotate Trash Spike"

    /// A real 1x1 PNG and a small JSON, named like a capture and its record.
    private static func makeFixture(in folder: URL, label: String, into report: inout Report) -> (URL, URL)? {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let png = folder.appendingPathComponent("\(fixturePrefix) \(label) \(stamp).png", isDirectory: false)
        let json = FileSink.recordURL(for: png)
        do {
            try pngData().write(to: png, options: .withoutOverwriting)
            try Data(#"{"spike":"trash","file":"\#(png.lastPathComponent)"}"#.utf8).write(to: json, options: .withoutOverwriting)
            return (png, json)
        } catch {
            report.line("  fixture write FAILED: \(describe(error))")
            return nil
        }
    }

    private static func leftoverFixtures(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .filter { $0.hasPrefix("\(fixturePrefix) leftover-") }
            .map { folder.appendingPathComponent($0, isDirectory: false) }
    }

    private static func pngData() -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        rep?.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: 0, y: 0)
        return rep?.representation(using: .png, properties: [:]) ?? Data()
    }

    // MARK: Probes

    private static func probeList(_ folder: URL) -> String {
        do {
            let count = try FileManager.default.contentsOfDirectory(atPath: folder.path).count
            return "OK (\(count) entries)"
        } catch {
            return "ERR \(describe(error))"
        }
    }

    private static func probeWrite(in folder: URL) -> String {
        let url = folder.appendingPathComponent(".\(fixturePrefix) probe \(UUID().uuidString)", isDirectory: false)
        do {
            try Data("probe".utf8).write(to: url, options: .withoutOverwriting)
            try? FileManager.default.removeItem(at: url)
            return "OK (folder writable)"
        } catch {
            return "ERR \(describe(error))"
        }
    }

    // MARK: Report

    private static var bookmarkFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("TrashSpike", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("chosen-folder.bookmark", isDirectory: false)
    }

    struct Report {
        private(set) var text = ""
        mutating func line(_ string: String) {
            text += string + "\n"
        }
    }

    private static func header(_ title: String) -> Report {
        var report = Report()
        let info = Bundle.main.infoDictionary ?? [:]
        report.line("== Trash Spike: \(title)")
        report.line("date: \(ISO8601DateFormatter().string(from: Date()))")
        report.line("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        report.line("bundle: \(Bundle.main.bundleIdentifier ?? "nil") \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))")
        report.line("app: \(Bundle.main.bundlePath)")
        #if DEBUG
        report.line("configuration: Debug")
        #else
        report.line("configuration: Release")
        #endif
        let container = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"]
        report.line("APP_SANDBOX_CONTAINER_ID: \(container ?? "nil (NOT SANDBOXED)")")
        report.line("home (sandbox view): \(FileManager.default.homeDirectoryForCurrentUser.path)")
        for key in entitlementKeys {
            report.line("entitlement \(key): \(entitlement(key))")
        }
        return report
    }

    private static let entitlementKeys = [
        "com.apple.security.app-sandbox",
        "com.apple.security.assets.pictures.read-write",
        "com.apple.security.files.user-selected.read-write",
        "com.apple.security.files.bookmarks.app-scope",
        "com.apple.security.automation.apple-events",
        "com.apple.security.get-task-allow"
    ]

    private static func entitlement(_ key: String) -> String {
        guard let task = SecTaskCreateFromSelf(nil) else { return "?" }
        guard let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) else { return "absent" }
        return "\(value)"
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var text = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " (underlying \(underlying.domain) \(underlying.code))"
        }
        return text
    }

    /// Shows `report` in an alert and puts it on the clipboard, so it can be pasted back.
    static func present(_ report: String) {
        log.notice("\(report, privacy: .public)")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        RunLoop.main.perform {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Trash Spike (report copied to clipboard)"
            alert.informativeText = report
            alert.runModal()
        }
    }
}

/// Menu target for the spike items.
@MainActor
final class TrashSpikeTarget: NSObject {
    static let shared = TrashSpikeTarget()

    @objc func runDefault() {
        Task { @MainActor in TrashSpike.present(await TrashSpike.runDefaultFolder()) }
    }

    @objc func chooseAndRun() {
        Task { @MainActor in
            guard let report = await TrashSpike.chooseAndRun() else { return }
            TrashSpike.present(report)
        }
    }

    @objc func runFromBookmark() {
        Task { @MainActor in TrashSpike.present(await TrashSpike.runChosenFromBookmark()) }
    }

    @objc func forget() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let file = support.appendingPathComponent("TrashSpike/chosen-folder.bookmark")
        let removed = (try? FileManager.default.removeItem(at: file)) != nil
        TrashSpike.present("Saved bookmark \(removed ? "removed" : "was not there"): \(file.path)")
    }
}
#endif
