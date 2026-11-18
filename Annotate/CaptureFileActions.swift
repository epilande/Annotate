import AppKit

/// What can be done with a saved capture and the capture folder: open, copy, show in Finder,
/// and open the folder. The system calls are injected, so tests leave Finder and the default
/// apps alone. Holding a chosen folder's security scope, and getting the overlay out of the way,
/// are the caller's part.
@MainActor
struct CaptureFileActions {
    /// Opens a file or folder in its default app. Returns whether it did.
    var open: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    /// Shows files selected in Finder.
    var reveal: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
    var fileExists: @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    /// Reads a file's bytes. Runs off the main actor.
    var readFile: @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    /// Where Copy puts a capture.
    var pasteboard: NSPasteboard = .general

    /// How copying a capture went.
    enum CopyOutcome {
        case copied
        /// The file is gone, and there is nothing to report: it drops out of the menu.
        case missing
        case failed(Error)
    }

    /// Puts the PNG at `file` on the pasteboard, as a capture's own copy does. The bytes are
    /// read off the main actor while the chosen folder's scope is held.
    func copy(_ file: URL, from folders: CaptureFolderStore) async -> CopyOutcome {
        let fileExists = fileExists
        let readFile = readFile
        let read: Result<Data, Error>? = await folders.withAccess { _ in
            guard fileExists(file) else { return nil }
            return Result { try readFile(file) }
        }
        switch read {
        case nil:
            return .missing
        case .failure(let error):
            return fileExists(file) ? .failed(error) : .missing
        case .success(let data):
            pasteboard.clearContents()
            guard pasteboard.setData(data, forType: .png) else { return .failed(CocoaError(.fileWriteUnknown)) }
            return .copied
        }
    }

    /// Creates `folder` if it is missing, so Finder has something to open.
    nonisolated static func prepareFolder(_ folder: URL) -> Result<URL, Error> {
        Result {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }

    nonisolated static func folderErrorMessage(_ error: Error) -> String {
        "Couldn't create the folder. \(error.localizedDescription)"
    }
}
