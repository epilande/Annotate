import AppKit
import ImageIO

// Recent Captures: the saved captures the status menu lists, newest first. There is no index.
// Each time the status menu opens, the capture folders are scanned again off the main actor,
// and the menu shows what the last scan found, plus any capture saved since it started.

/// A saved capture the Recent Captures menu lists.
struct RecentCapture: Equatable, Sendable {
    /// The PNG, made `canonical`, so one file reached two ways is one capture.
    let file: URL
    /// The file's creation date when a scan found it, or when the capture reported it saved.
    let createdAt: Date
    /// The file's version when a scan found it. Nil for a capture recorded from its result.
    var version: FileVersion?

    /// What tells two captures apart.
    var path: String { file.path }

    /// `file` with its folder's symlinks resolved, `/private` included, so a capture reported
    /// by its save and found by a scan is the same file. A folder that isn't there stays as is.
    nonisolated static func canonical(_ file: URL) -> URL {
        let folder = file.deletingLastPathComponent()
        guard let resolved = realpath(folder.path, nil) else { return file.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
            .appendingPathComponent(file.lastPathComponent, isDirectory: false)
    }
}

/// What tells two versions of a file at one path apart, so a thumbnail is made again when the
/// file is replaced or edited.
struct FileVersion: Equatable, Sendable {
    let modifiedAt: Date?
    let size: Int?

    /// The version of the file at `url`, or nil when it can't be read.
    nonisolated static func of(_ url: URL) -> FileVersion? {
        // A URL caches the values it read, so read through a fresh copy.
        var url = url
        url.removeAllCachedResourceValues()
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return nil
        }
        return FileVersion(values)
    }

    nonisolated init(modifiedAt: Date?, size: Int?) {
        self.modifiedAt = modifiedAt
        self.size = size
    }

    nonisolated init(_ values: URLResourceValues) {
        self.init(modifiedAt: values.contentModificationDate, size: values.fileSize)
    }
}

/// A thumbnail, and the version of the file it was made from when that is known.
struct CachedThumbnail: Sendable {
    let image: CGImage
    let version: FileVersion?
}

/// What one scan of the capture folders found.
struct RecentCaptureScan: Sendable {
    /// Newest first, at most `RecentCaptureScanner.limit`.
    var captures: [RecentCapture]
    /// The chosen folder's name when it couldn't be reached, so only the default folder was
    /// scanned.
    var missedFolder: String?
    /// Thumbnails for the captures that had none of their version yet, by `RecentCapture.path`.
    var thumbnails: [String: CachedThumbnail] = [:]
}

/// Finds saved captures in the capture folders by name: the names `FileSink` gives them.
enum RecentCaptureScanner {
    /// How many captures the menu lists.
    static let limit = 8

    /// The parts of a capture file name, `Annotate 2026-11-01 at 10.23.45 (2).png`, that order
    /// two captures made in the same second.
    struct FileName: Equatable, Sendable {
        /// `2026-11-01 at 10.23.45`.
        let stamp: String
        /// 1 for the name without a suffix, else the number in ` (n)`.
        let copy: Int
    }

    /// The name's parts when it is one `FileSink` gives a capture, else nil. Hidden files,
    /// including the `.Annotate-*.tmp` files a save writes first, are never captures, nor is any
    /// PNG named some other way, such as one the user renamed.
    nonisolated static func parse(_ name: String) -> FileName? {
        let prefix = "Annotate ", suffix = ".png"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        var rest = Substring(name.dropFirst(prefix.count).dropLast(suffix.count))
        var copy = 1
        if rest.hasSuffix(")"), let open = rest.range(of: " (", options: .backwards) {
            let digits = rest[open.upperBound..<rest.index(before: rest.endIndex)]
            guard let number = Int(digits), number >= 2, digits.allSatisfy(\.isASCII), digits.first != "0"
            else { return nil }
            copy = number
            rest = rest[..<open.lowerBound]
        }
        // `yyyy-MM-dd at HH.mm.ss`, digit for digit.
        let template = "0000-00-00 at 00.00.00"
        guard rest.count == template.count,
            zip(rest, template).allSatisfy({ char, slot in
                slot == "0" ? char.isASCII && char.isNumber : char == slot
            })
        else { return nil }
        return FileName(stamp: String(rest), copy: copy)
    }

    /// The newest captures in `folders`, made after `cutoff`, newest first. A folder that is
    /// missing or can't be read adds nothing. One file reached through two folders, as when
    /// the chosen folder is the default one, counts once.
    nonisolated static func captures(in folders: [URL], after cutoff: Date, limit: Int = limit) -> [RecentCapture] {
        var seen = Set<String>()
        var found: [RecentCapture] = []
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        for folder in folders {
            guard
                let files = try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            else { continue }
            // Each capture is named by its folder's real path, resolved once per folder.
            let realFolder = RecentCapture.canonical(folder.appendingPathComponent("_")).deletingLastPathComponent()
            for listed in files {
                let name = listed.lastPathComponent
                guard parse(name) != nil,
                    let values = try? listed.resourceValues(forKeys: Set(keys)),
                    values.isRegularFile == true,
                    let createdAt = values.creationDate ?? values.contentModificationDate,
                    createdAt > cutoff
                else { continue }
                let file = realFolder.appendingPathComponent(name, isDirectory: false)
                guard seen.insert(file.path).inserted else { continue }
                found.append(RecentCapture(file: file, createdAt: createdAt, version: FileVersion(values)))
            }
        }
        return Array(found.sorted(by: isNewer).prefix(limit))
    }

    /// Newest by creation date. Two captures made at the same moment, as a ` (2)` can be,
    /// fall back on their names, where a later stamp or a higher copy is newer.
    nonisolated static func isNewer(_ lhs: RecentCapture, than rhs: RecentCapture) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        if let left = parse(lhs.file.lastPathComponent), let right = parse(rhs.file.lastPathComponent) {
            if left.stamp != right.stamp { return left.stamp > right.stamp }
            if left.copy != right.copy { return left.copy > right.copy }
        }
        return lhs.path > rhs.path
    }

    /// Scans the folder `bookmark` holds, when it can be reached, and `defaultFolder`, holding
    /// the chosen folder's security scope throughout. Makes a thumbnail for each capture whose
    /// version isn't the one in `thumbnailed`, by path. Runs off the main actor.
    nonisolated static func scan(
        chosenFolder bookmark: Data?, defaultFolder: URL, after cutoff: Date, thumbnailed: [String: FileVersion]
    ) async -> RecentCaptureScan {
        await CaptureFolderStore.withAccess(to: bookmark) { chosen in
            let captures = Self.captures(in: [chosen, defaultFolder].compactMap { $0 }, after: cutoff)
            var thumbnails: [String: CachedThumbnail] = [:]
            for capture in captures where capture.version == nil || thumbnailed[capture.path] != capture.version {
                if let image = RecentCaptureThumbnail.make(fromFileAt: capture.file) {
                    thumbnails[capture.path] = CachedThumbnail(image: image, version: capture.version)
                }
            }
            let missedFolder = chosen == nil ? bookmark.map(CaptureFolderBookmark.folderName(of:)) : nil
            return RecentCaptureScan(captures: captures, missedFolder: missedFolder, thumbnails: thumbnails)
        }
    }
}

/// The picture beside each recent capture: the capture fit in a fixed box, drawn at 2x.
enum RecentCaptureThumbnail {
    /// Every row's image is this size, in points, so the titles line up.
    static let box = NSSize(width: 64, height: 40)
    /// Thumbnail pixels per point.
    static let scale: CGFloat = 2

    /// The thumbnail's size in pixels for an image of `size` pixels: fit in the box at 2x,
    /// keeping its aspect ratio, and never larger than the image.
    nonisolated static func fittedPixelSize(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let ratio = min(1, box.width * scale / size.width, box.height * scale / size.height)
        return CGSize(
            width: max(1, (size.width * ratio).rounded()),
            height: max(1, (size.height * ratio).rounded()))
    }

    /// A thumbnail of the PNG at `url`, decoded at thumbnail size rather than in full, or nil
    /// when it can't be read.
    nonisolated static func make(fromFileAt url: URL) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let fitted = fittedPixelSize(for: CGSize(width: width, height: height))
        guard fitted.width > 0 else { return nil }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(max(fitted.width, fitted.height)),
            ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /// A thumbnail of a capture's image, from memory.
    nonisolated static func make(from image: CGImage) -> CGImage? {
        let fitted = fittedPixelSize(for: CGSize(width: image.width, height: image.height))
        guard fitted.width > 0 else { return nil }
        if Int(fitted.width) == image.width, Int(fitted.height) == image.height { return image }
        return image.resized(width: Int(fitted.width), height: Int(fitted.height))
    }

    /// The menu item's image: `thumbnail` centered on a faint rounded backing that fills the
    /// box, or the backing alone while the thumbnail is still being made.
    @MainActor
    static func menuImage(_ thumbnail: CGImage?) -> NSImage {
        let image = NSImage(size: box, flipped: false) { rect in
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            guard let thumbnail, let context = NSGraphicsContext.current?.cgContext else { return true }
            let size = CGSize(width: CGFloat(thumbnail.width) / scale, height: CGFloat(thumbnail.height) / scale)
            // On the 2x pixel grid, so a thumbnail that fills the box draws pixel for pixel.
            let origin = CGPoint(
                x: ((rect.width - size.width) / 2 * scale).rounded() / scale,
                y: ((rect.height - size.height) / 2 * scale).rounded() / scale)
            context.interpolationQuality = .high
            context.draw(thumbnail, in: CGRect(origin: origin, size: size))
            return true
        }
        return image
    }
}

/// The recent captures the status menu lists, newest first, kept from the last scan plus any
/// capture saved since. Scans run off the main actor, so the menu never waits on the disk.
@MainActor
final class RecentCaptureStore {
    /// Newest first, at most `RecentCaptureScanner.limit`.
    private(set) var captures: [RecentCapture] = []
    /// The chosen folder's name when the last scan couldn't reach it.
    private(set) var missedFolder: String?
    /// Runs after anything above or any thumbnail changes.
    var onChange: (() -> Void)?
    /// The scan in flight, if any. Tests await it.
    private(set) var scanTask: Task<Void, Never>?
    /// The latest thumbnail being made from a capture's image. Tests await it.
    private(set) var thumbnailTask: Task<Void, Never>?
    /// The clock `record` and `clear` read. Tests replace it.
    var now: () -> Date = Date.init
    /// Scans the folders: the chosen folder's bookmark, the default folder, the Clear Menu
    /// cutoff, and the file version each cached thumbnail was made from. Tests replace it to
    /// hold a scan.
    var scan:
        @Sendable (_ chosenFolder: Data?, _ defaultFolder: URL, _ cutoff: Date, _ thumbnailed: [String: FileVersion]) async
        -> RecentCaptureScan = { await RecentCaptureScanner.scan(chosenFolder: $0, defaultFolder: $1, after: $2, thumbnailed: $3) }

    private let settings: SettingsStore
    /// The chosen folder, and the default folder, as they stand when a scan starts.
    private let folders: () -> (chosen: CaptureFolderStore, defaultFolder: URL)
    private var thumbnails: [String: CachedThumbnail] = [:]
    /// Captures recorded since the latest scan started, which it may have missed.
    private var recordedSinceScan: [RecentCapture] = []
    /// Paths of captures found gone since the latest scan started, which it may still list.
    private var removedSinceScan: Set<String> = []
    /// Counts scans, so only the latest one started is kept.
    private var scanGeneration = 0

    init(settings: SettingsStore, folders: @escaping () -> (chosen: CaptureFolderStore, defaultFolder: URL)) {
        self.settings = settings
        self.folders = folders
    }

    /// Captures made at or before this are hidden: Clear Menu sets it.
    private var cutoff: Date { Date(timeIntervalSince1970: settings[.recentCapturesClearedAt]) }

    func thumbnail(for capture: RecentCapture) -> CGImage? {
        thumbnails[capture.path]?.image
    }

    /// Puts a capture that saved a file at the top straight away, from the result in memory,
    /// with its thumbnail made from its image. A capture saved only to the clipboard isn't
    /// listed.
    func record(_ result: CaptureResult) {
        guard let file = result.savedFile else { return }
        let capture = RecentCapture(file: RecentCapture.canonical(file), createdAt: now())
        recordedSinceScan.append(capture)
        removedSinceScan.remove(capture.path)
        captures = merged([capture], into: captures)
        prune()
        let image = result.capture.image
        thumbnailTask = Task { [weak self] in
            let thumbnail = await Self.makeThumbnail(from: image, of: capture.file)
            guard let self, let thumbnail, self.captures.contains(capture) else { return }
            self.thumbnails[capture.path] = thumbnail
            self.onChange?()
        }
        onChange?()
    }

    /// The thumbnail of a capture's image, with the version of the file it was saved to, so a
    /// later scan keeps it unless the file has changed since.
    nonisolated private static func makeThumbnail(from image: CGImage, of file: URL) async -> CachedThumbnail? {
        RecentCaptureThumbnail.make(from: image).map { CachedThumbnail(image: $0, version: FileVersion.of(file)) }
    }

    /// Scans the folders again, in the background. A scan started before a later one is
    /// dropped when it lands.
    func refresh() {
        scanGeneration += 1
        let generation = scanGeneration
        recordedSinceScan = []
        removedSinceScan = []
        let (chosen, defaultFolder) = folders()
        let bookmark = chosen.bookmark
        let cutoff = cutoff
        let thumbnailed = thumbnails.compactMapValues(\.version)
        let scan = scan
        scanTask = Task { [weak self] in
            let found = await scan(bookmark, defaultFolder, cutoff, thumbnailed)
            self?.land(found, generation: generation)
        }
    }

    /// Keeps what a scan found, which is the truth for every capture saved before it started.
    /// Captures recorded since stay too, since it may have missed them, and captures found gone
    /// since stay out, since it may have listed them.
    private func land(_ scan: RecentCaptureScan, generation: Int) {
        guard generation == scanGeneration else { return }
        missedFolder = scan.missedFolder
        let removed = removedSinceScan
        let found = scan.captures.filter { !removed.contains($0.path) }
        // A capture recorded from its result keeps its thumbnail until its file changes.
        for capture in found where scan.thumbnails[capture.path] == nil {
            if let cached = thumbnails[capture.path], cached.version != capture.version {
                thumbnails[capture.path] = nil
            }
        }
        thumbnails.merge(scan.thumbnails) { _, new in new }
        captures = merged(recordedSinceScan, into: found)
        prune()
        onChange?()
    }

    /// Keeps the thumbnails and the captures recorded since the last scan to what is listed, so
    /// neither grows past the limit between scans.
    private func prune() {
        let listed = Set(captures.map(\.path))
        thumbnails = thumbnails.filter { listed.contains($0.key) }
        recordedSinceScan.removeAll { !listed.contains($0.path) }
    }

    /// Clear Menu: hides every capture made until now. The files stay where they are.
    func clear() {
        settings[.recentCapturesClearedAt] = now().timeIntervalSince1970
        captures = []
        recordedSinceScan = []
        thumbnails = [:]
        onChange?()
    }

    /// Drops a capture whose file is gone.
    func remove(_ file: URL) {
        let path = RecentCapture.canonical(file).path
        captures.removeAll { $0.path == path }
        recordedSinceScan.removeAll { $0.path == path }
        removedSinceScan.insert(path)
        thumbnails[path] = nil
        onChange?()
    }

    /// `newer` over `list`, newest first, each file once, without hidden captures, at most
    /// `RecentCaptureScanner.limit`.
    private func merged(_ newer: [RecentCapture], into list: [RecentCapture]) -> [RecentCapture] {
        let newerPaths = Set(newer.map(\.path))
        let cutoff = cutoff
        let kept = (newer + list.filter { !newerPaths.contains($0.path) })
            .filter { $0.createdAt > cutoff }
            .sorted(by: RecentCaptureScanner.isNewer)
        return Array(kept.prefix(RecentCaptureScanner.limit))
    }
}
