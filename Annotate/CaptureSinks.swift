import AppKit
import os

private let log = Logger(subsystem: "com.epilande.Annotate", category: "Capture")

/// Saves each capture as a PNG in a folder, named after its time the way macOS names
/// screenshots: `Annotate 2026-11-01 at 10.23.45.png`, then ` (2)`, ` (3)` on collision.
struct FileSink: CaptureSink {
    /// The default folder, which also takes a capture the chosen folder can't.
    var folder: URL
    /// Holds the folder chosen in Settings, read for each capture.
    var chosenFolder: CaptureFolderStore?
    /// Writes each capture's temporary file. Debug builds can make it fail on purpose; see
    /// `failSavesArgument`.
    var writeBytes: @Sendable (Data, URL) throws -> Void = writeWithoutOverwriting

    var destination: CaptureDestination { .file }

    /// `~/Pictures/Annotate`. Pictures is reachable through the app's Pictures entitlement
    /// and, unlike Desktop, Documents, and Downloads, has no first-access prompt that would
    /// open under the overlay.
    nonisolated static var defaultFolder: URL {
        realHomeDirectory
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("Annotate", isDirectory: true)
    }

    /// The user's home folder. In the sandbox `homeDirectoryForCurrentUser` is the app's
    /// container, which would hide captures inside `~/Library/Containers`.
    nonisolated static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    func deliver(_ capture: Capture, png: Data) async throws -> CaptureDelivery {
        let baseName = Self.baseName(for: capture.capturedAt)
        guard let chosenFolder, let bookmark = chosenFolder.bookmark else {
            return .file(try await Self.write(png, baseName: baseName, in: folder, writeBytes: writeBytes))
        }
        let chosen = await Self.write(png, baseName: baseName, bookmark: bookmark, writeBytes: writeBytes)
        if let renewed = chosen.renewedBookmark {
            chosenFolder.renew(bookmark, with: renewed)
        }
        if let file = chosen.file { return .file(file) }
        let file = try await Self.write(png, baseName: baseName, in: folder, writeBytes: writeBytes)
        return .file(file, missedFolder: CaptureFolderBookmark.folderName(of: bookmark))
    }

    /// Writes `data` to the folder `bookmark` leads to, holding its security scope for the whole
    /// write. Returns a nil file when the folder is gone or the write failed, and a replacement
    /// when macOS calls the bookmark stale, as it does once the folder has moved. A false from
    /// `startAccessingSecurityScopedResource` is no verdict: folders under Pictures need no
    /// scope, so the write decides.
    nonisolated static func write(
        _ data: Data, baseName: String, bookmark: Data,
        writeBytes: @Sendable (Data, URL) throws -> Void = writeWithoutOverwriting
    ) async -> (file: URL?, renewedBookmark: Data?) {
        guard let folder = CaptureFolderBookmark.resolve(bookmark) else { return (nil, nil) }
        let isAccessing = folder.url.startAccessingSecurityScopedResource()
        defer { if isAccessing { folder.url.stopAccessingSecurityScopedResource() } }
        let renewed = folder.isStale ? try? CaptureFolderBookmark.make(for: folder.url) : nil
        do {
            return (try await write(data, baseName: baseName, in: folder.url, writeBytes: writeBytes), renewed)
        } catch {
            log.error("Capture couldn't be saved to the chosen folder: \(error.localizedDescription)")
            return (nil, renewed)
        }
    }

    /// `Annotate 2026-11-01 at 10.23.45`, in the current time zone.
    nonisolated static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Annotate \(formatter.string(from: date))"
    }

    /// The file name for the `attempt`th try at `baseName`: no suffix first, then ` (2)` on.
    nonisolated static func fileName(_ baseName: String, attempt: Int) -> String {
        attempt <= 1 ? "\(baseName).png" : "\(baseName) (\(attempt)).png"
    }

    /// Writes `data` under the first free name, creating the folder if needed. The bytes go
    /// to a hidden temporary file in the same folder first and are moved into place whole, so
    /// a write that fails partway never leaves a truncated image under a capture's name. Each
    /// move refuses to overwrite, so two captures in the same second never replace each other.
    /// Runs off the main actor. `writeBytes` writes the temporary file; tests make it fail
    /// partway.
    nonisolated static func write(
        _ data: Data, baseName: String, in folder: URL,
        writeBytes: @Sendable (Data, URL) throws -> Void = writeWithoutOverwriting
    ) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(temporaryFileName(), isDirectory: false)
        // Whatever happens, the temporary file goes; after a move there is nothing left to remove.
        defer { try? fileManager.removeItem(at: temporary) }
        try writeBytes(data, temporary)
        var attempt = 1
        while true {
            let url = folder.appendingPathComponent(fileName(baseName, attempt: attempt), isDirectory: false)
            do {
                try fileManager.moveItem(at: temporary, to: url)
                return url
            } catch CocoaError.fileWriteFileExists where attempt < maxAttempts {
                attempt += 1
            }
        }
    }

    nonisolated static let writeWithoutOverwriting: @Sendable (Data, URL) throws -> Void = {
        try $0.write(to: $1, options: .withoutOverwriting)
    }

    #if DEBUG
    /// Launch a debug build with this argument and every save fails before any bytes land, so
    /// the save-failure report can be checked live: the overlay's HUD, or the alert with Hide
    /// Tool Feedback on. The clipboard copy still works.
    /// `open Annotate.app --args --fail-capture-saves`
    nonisolated static let failSavesArgument = "--fail-capture-saves"

    /// What a save throws when `failSavesArgument` is set. The alert's detail names the switch,
    /// so the failure is never mistaken for a real one.
    struct ForcedSaveFailure: LocalizedError {
        var errorDescription: String? { "This debug build was launched with \(FileSink.failSavesArgument)." }
    }
    #endif

    /// A hidden name no capture uses, unique per write.
    nonisolated static func temporaryFileName() -> String {
        ".Annotate-\(UUID().uuidString).png.tmp"
    }

    nonisolated private static let maxAttempts = 1000
}

/// Puts each capture on a pasteboard as PNG.
struct ClipboardSink: CaptureSink {
    var pasteboard: NSPasteboard = .general

    var destination: CaptureDestination { .clipboard }

    func deliver(_ capture: Capture, png: Data) async throws -> CaptureDelivery {
        pasteboard.clearContents()
        guard pasteboard.setData(png, forType: .png) else { throw CocoaError(.fileWriteUnknown) }
        return .clipboard
    }
}
