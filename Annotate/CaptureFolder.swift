import Foundation

/// Security-scoped bookmarks of a folder. The sandbox grants a folder from `NSOpenPanel` for one
/// launch; the bookmark brings that grant back on later launches.
enum CaptureFolderBookmark {
    /// What a bookmark leads to. `url` must be the instance that starts the security scope.
    struct Resolved {
        let url: URL
        let isStale: Bool
    }

    static func make(for folder: URL) throws -> Data {
        try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// The folder, or nil when it is gone, in the Trash, or on a volume that isn't mounted.
    /// Never mounts a volume or shows UI: this runs for each capture, and a dialog would land
    /// under the overlay.
    static func resolve(_ bookmark: Data) -> Resolved? {
        var isStale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale),
            !isInTrash(url)
        else { return nil }
        return Resolved(url: url, isStale: isStale)
    }

    /// The path a bookmark was made from, which needs nothing to be reachable.
    static func path(of bookmark: Data) -> String? {
        URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: bookmark)?.path
    }

    /// The folder's name, for telling the user which folder was missed.
    static func folderName(of bookmark: Data) -> String {
        path(of: bookmark).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Your Folder"
    }

    /// A bookmark follows a folder into the Trash, where saved captures would go unnoticed
    /// until it is emptied.
    static func isInTrash(_ url: URL) -> Bool {
        !Set(url.pathComponents).isDisjoint(with: [".Trash", ".Trashes"])
    }
}

/// Where captures should be saved, as the chosen folder stands right now.
enum CaptureFolderState: Equatable {
    /// No folder is chosen.
    case standard
    case chosen(URL)
    /// A folder is chosen but can't be reached, so captures go to the default folder until it
    /// comes back. `path` is where it was, when the bookmark still says.
    case unreachable(path: String?)
}

/// The folder chosen for captures in Settings. Without one, captures go to
/// `FileSink.defaultFolder`.
struct CaptureFolderStore {
    let settings: SettingsStore

    var bookmark: Data? {
        let stored = settings[.captureFolderBookmark]
        return stored.isEmpty ? nil : stored
    }

    var state: CaptureFolderState {
        guard let bookmark else { return .standard }
        if let folder = CaptureFolderBookmark.resolve(bookmark) { return .chosen(folder.url) }
        return .unreachable(path: CaptureFolderBookmark.path(of: bookmark))
    }

    /// Remembers `folder`, which must come straight from `NSOpenPanel` while its grant is live.
    func choose(_ folder: URL) throws {
        settings[.captureFolderBookmark] = try CaptureFolderBookmark.make(for: folder)
    }

    func useDefaultFolder() {
        settings.removeValue(for: .captureFolderBookmark)
    }

    /// Replaces a stale bookmark, unless the user chose another folder while it was being renewed.
    func renew(_ old: Data, with new: Data) {
        guard bookmark == old else { return }
        settings[.captureFolderBookmark] = new
    }

    /// Runs `body` with the chosen folder's security scope held, for handing it or a file in it
    /// to Finder. Runs `body` with nil when no chosen folder can be reached.
    func withAccess(_ body: (URL?) -> Void) {
        guard let folder = bookmark.flatMap(CaptureFolderBookmark.resolve) else {
            body(nil)
            return
        }
        let isAccessing = folder.url.startAccessingSecurityScopedResource()
        defer { if isAccessing { folder.url.stopAccessingSecurityScopedResource() } }
        body(folder.url)
    }

    /// `withAccess` for work that awaits: the scope stays held until `body` returns, across
    /// every suspension in it. The bookmark is read on the caller's actor, then resolved off
    /// it, and `body` runs off it too, so a scan or a file read never holds up a menu.
    func withAccess<T: Sendable>(
        isolation: isolated (any Actor)? = #isolation, _ body: @Sendable (URL?) async throws -> T
    ) async rethrows -> T {
        try await Self.withAccess(to: bookmark, body)
    }

    /// The same for a bookmark read earlier, or nil for no chosen folder.
    nonisolated static func withAccess<T: Sendable>(
        to bookmark: Data?, _ body: @Sendable (URL?) async throws -> T
    ) async rethrows -> T {
        guard let folder = bookmark.flatMap(CaptureFolderBookmark.resolve) else {
            return try await body(nil)
        }
        let isAccessing = folder.url.startAccessingSecurityScopedResource()
        defer { if isAccessing { folder.url.stopAccessingSecurityScopedResource() } }
        return try await body(folder.url)
    }
}
