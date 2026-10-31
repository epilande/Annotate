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

    /// Parses a link such as `annotate://show` or `annotate://tool/arrow`: the host is the command
    /// and the path its value, matched like `init?(path:)`. Returns nil for another scheme, a
    /// missing command, a user, password, port, query, or fragment, or a path `init?(path:)`
    /// rejects.
    init?(url: URL, scheme: String = AnnotateCommand.urlScheme) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == scheme.lowercased(),
            let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil, components.port == nil,
            components.query == nil, components.fragment == nil
        else { return nil }
        self.init(path: host + components.path)
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

    /// Runs a link's command and shows its HUD. Returns nil without doing anything when URL
    /// commands are off in Settings or the link isn't a command.
    @discardableResult
    func openCommandURL(_ url: URL) -> AnnotateCommand.Outcome? {
        guard settings[.urlCommandsEnabled] else {
            log.info("Ignored a link because URL commands are off: \(url.absoluteString, privacy: .public)")
            return nil
        }
        guard let command = AnnotateCommand(url: url) else {
            log.info("Ignored a link that isn't a command: \(url.absoluteString, privacy: .public)")
            return nil
        }
        return command.run(on: self)
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
