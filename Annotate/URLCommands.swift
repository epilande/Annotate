import Cocoa
import os

// `annotate://` links. Each link names an `AnnotateCommand` in its path form, so
// `annotate://tool/arrow` runs `.tool(.arrow)` the same way the Select Tool action does.

extension AnnotateCommand {
    /// The scheme this build opens. Debug builds register their own, so a development copy never
    /// takes links meant for the installed app. Keep in sync with `ANNOTATE_URL_SCHEME` in
    /// `project.yml`, which puts the scheme in `Info.plist`.
    #if DEBUG
    static let urlScheme = "annotate-debug"
    #else
    static let urlScheme = "annotate"
    #endif

    /// Why a link isn't a command. The raw value is a fixed phrase that holds nothing from the
    /// link, so it's safe to log in the clear.
    enum LinkRejection: String, Error, Equatable {
        case unparseable = "it can't be parsed"
        case otherScheme = "it has another scheme"
        case missingCommand = "it names no command"
        case extraParts = "it has a user, password, port, query, or fragment"
        case unknownCommand = "its command or value is unknown"
    }

    /// Parses a link such as `annotate://show` or `annotate://tool/arrow`: the host is the command
    /// and the path its value, matched like `init?(path:)`. Fails for another scheme, a missing
    /// command, a user, password, port, query, or fragment, or a path `init?(path:)` rejects.
    static func parse(url: URL, scheme: String = AnnotateCommand.urlScheme) -> Result<AnnotateCommand, LinkRejection> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.unparseable)
        }
        guard components.scheme?.lowercased() == scheme.lowercased() else { return .failure(.otherScheme) }
        guard let host = components.host, !host.isEmpty else { return .failure(.missingCommand) }
        guard components.user == nil, components.password == nil, components.port == nil,
            components.query == nil, components.fragment == nil
        else { return .failure(.extraParts) }
        guard let command = AnnotateCommand(path: host + components.path) else {
            return .failure(.unknownCommand)
        }
        return .success(command)
    }

    /// `parse(url:scheme:)` without the reason.
    init?(url: URL, scheme: String = AnnotateCommand.urlScheme) {
        guard case .success(let command) = Self.parse(url: url, scheme: scheme) else { return nil }
        self = command
    }

    /// A link with only its scheme, host, and path. Drops the user, password, port, query, and
    /// fragment, where a pasted or forwarded link could carry a token or other private data, and
    /// names which of them were there. Logged as private all the same, since even the host and
    /// path of a rejected link came from whoever sent it. Keeps percent-encoding, so the
    /// result is one line however the link was built.
    static func logDescription(of url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<unparseable link>"
        }
        let host = components.percentEncodedHost.map { "//" + $0 } ?? ""
        let link = (components.scheme.map { $0 + ":" } ?? "") + host + components.percentEncodedPath
        let parts: [(name: String, isPresent: Bool)] = [
            ("user", components.percentEncodedUser != nil),
            ("password", components.percentEncodedPassword != nil),
            ("port", components.port != nil),
            ("query", components.percentEncodedQuery != nil),
            ("fragment", components.percentEncodedFragment != nil),
        ]
        let dropped = parts.filter(\.isPresent).map(\.name)
        return dropped.isEmpty ? link : "\(link) (dropped \(dropped.joined(separator: ", ")))"
    }
}

private let log = Logger(subsystem: "com.epilande.Annotate", category: "URLCommands")

extension AppDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        // A link that launches the app can arrive before launch finishes, when there is no
        // overlay to open yet.
        guard hasFinishedLaunching else {
            pendingCommandURLs += urls
            return
        }
        urls.forEach { openCommandURL($0) }
    }

    /// Runs a link's command and shows its HUD. Then, if opening the link activated Annotate and
    /// no overlay took keyboard input, hands focus back to the previous app. Returns nil without doing anything when URL
    /// commands are off in Settings or the link isn't a command.
    ///
    /// A rejected link is logged with a fixed reason in the clear and the link itself as private,
    /// so `log stream` shows why a link was ignored without showing what it held.
    @discardableResult
    func openCommandURL(_ url: URL) -> AnnotateCommand.Outcome? {
        // After the command, so a link that opens the overlay keeps focus. A link that does
        // nothing hands focus back too.
        defer { linkFocusHandoff?.linkDidRun(keepsFocus: isOverlayKeyWindow) }
        guard settings[.urlCommandsEnabled] else {
            let link = AnnotateCommand.logDescription(of: url)
            log.info("Ignored a link because URL commands are off: \(link, privacy: .private)")
            return nil
        }
        switch AnnotateCommand.parse(url: url) {
        case .success(let command):
            return command.run(on: self)
        case .failure(let rejection):
            let link = AnnotateCommand.logDescription(of: url)
            log.info(
                "Ignored a link because \(rejection.rawValue, privacy: .public): \(link, privacy: .private)")
            return nil
        }
    }

    /// Runs the links that arrived during launch on the next run-loop pass, after the Always-On
    /// restore that launch queues.
    func runPendingCommandURLs() {
        guard !pendingCommandURLs.isEmpty else { return }
        let urls = pendingCommandURLs
        pendingCommandURLs = []
        DispatchQueue.main.async {
            urls.forEach { self.openCommandURL($0) }
        }
    }
}
