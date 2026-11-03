import AppKit

/// Saves each capture as a PNG in a folder, named after its time the way macOS names
/// screenshots: `Annotate 2026-11-01 at 10.23.45.png`, then ` (2)`, ` (3)` on collision.
struct FileSink: CaptureSink {
    var folder: URL

    /// `~/Pictures/Annotate`. Pictures is reachable through the app's Pictures entitlement
    /// and, unlike Desktop, Documents, and Downloads, has no first-access prompt that would
    /// open under the overlay.
    static var defaultFolder: URL {
        realHomeDirectory
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("Annotate", isDirectory: true)
    }

    /// The user's home folder. In the sandbox `homeDirectoryForCurrentUser` is the app's
    /// container, which would hide captures inside `~/Library/Containers`.
    static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    func deliver(_ capture: Capture, png: Data) async throws -> CaptureDelivery {
        let baseName = Self.baseName(for: capture.capturedAt)
        return .file(try await Self.write(png, baseName: baseName, in: folder))
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

    /// Writes `data` under the first free name, creating the folder if needed. Each attempt
    /// refuses to overwrite, so two captures in the same second never replace each other.
    /// Runs off the main actor.
    nonisolated static func write(_ data: Data, baseName: String, in folder: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var attempt = 1
        while true {
            let url = folder.appendingPathComponent(fileName(baseName, attempt: attempt), isDirectory: false)
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists where attempt < maxAttempts {
                attempt += 1
            }
        }
    }

    nonisolated private static let maxAttempts = 1000
}

/// Puts each capture on a pasteboard as PNG.
struct ClipboardSink: CaptureSink {
    var pasteboard: NSPasteboard = .general

    func deliver(_ capture: Capture, png: Data) async throws -> CaptureDelivery {
        pasteboard.clearContents()
        guard pasteboard.setData(png, forType: .png) else { throw CocoaError(.fileWriteUnknown) }
        return .clipboard
    }
}
