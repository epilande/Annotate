import SwiftUI

struct CaptureSettingsView: View {
    var navigation: SettingsNavigation
    private let folders: CaptureFolderStore
    private let notifier: CaptureNotifying
    @AppStorage(.afterCapture) private var afterCapture
    @State private var hasScreenCaptureAccess = ScreenSampler.shared.hasScreenCaptureAccess
    @State private var folderState: CaptureFolderState
    @State private var notificationAccess: CaptureNotificationAccess?
    /// Why the last folder action failed, until one next succeeds.
    @State private var folderError: String?

    static let screenCaptureSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// The Notifications pane of System Settings, open at Annotate.
    static var notificationSettingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")
    }

    init(
        navigation: SettingsNavigation = SettingsNavigation(),
        folders: CaptureFolderStore? = nil,
        notifier: CaptureNotifying? = nil
    ) {
        self.navigation = navigation
        let folders = folders ?? AppDelegate.shared?.captureFolders ?? CaptureFolderStore(settings: .standard)
        self.folders = folders
        self.notifier = notifier ?? AppDelegate.shared?.captureNotifier ?? SilentCaptureNotifier()
        _folderState = State(initialValue: folders.state)
    }

    /// The default capture folder with the home folder shown as `~`.
    static var folderDisplayPath: String { displayPath(of: FileSink.defaultFolder) }

    /// `folder`'s path with the home folder shown as `~`.
    nonisolated static func displayPath(of folder: URL) -> String {
        let path = folder.path
        let home = FileSink.realHomeDirectory.path
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// The folder row's path: the folder captures go to, or the one that can't be reached.
    static func displayPath(of state: CaptureFolderState) -> String {
        switch state {
        case .standard: folderDisplayPath
        case .chosen(let folder): displayPath(of: folder)
        case .unreachable(let path): path.map { displayPath(of: URL(fileURLWithPath: $0)) } ?? "Unknown folder"
        }
    }

    /// The note under the folder row while the chosen folder can't be reached.
    static var unreachableFolderMessage: String {
        "This folder can't be reached, so captures go to \(folderDisplayPath) until it comes back."
    }

    /// What captures do with After Capture at `afterCapture`.
    static func captureSummary(_ afterCapture: AfterCapture) -> String {
        let what = "Capture Screen takes a PNG of the display, and Capture Area of a part you drag out, with the board and annotations as they appear."
        switch afterCapture {
        case .save: return "\(what) It is saved to this folder."
        case .copy: return "\(what) It is copied to the clipboard, and no file is saved."
        case .both: return "\(what) It is saved to this folder and copied to the clipboard."
        }
    }

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .capture)
            }

            Section {
                Picker("After capture", selection: $afterCapture) {
                    ForEach(AfterCapture.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .accessibilityIdentifier("capture.afterCapture")
                folderRows
                    .disabled(!afterCapture.savesFile)
                Text(Self.captureSummary(afterCapture))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                SettingsHeader(
                    icon: "camera.viewfinder",
                    color: .teal,
                    title: "Capture",
                    subtitle: "Save the display or an area with its annotations"
                )
            }

            Section {
                notificationRow
            } header: {
                SettingsHeader(
                    icon: "bell.badge",
                    color: .orange,
                    title: "Notifications",
                    subtitle: "Hear about captures made with the overlay closed"
                )
            }

            Section {
                screenRecordingRow
            } header: {
                SettingsHeader(
                    icon: "record.circle",
                    color: .red,
                    title: "Screen Recording",
                    subtitle: "Needed to read what is on screen"
                )
            }
        }
        .formStyle(.grouped)
        .settingsScrollEdgeEffect()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user comes back here after flipping the switch in System Settings.
            hasScreenCaptureAccess = ScreenSampler.shared.refreshScreenCaptureAccess()
            folderState = folders.state
            Task { notificationAccess = await notifier.access() }
        }
        .onAppear(perform: requestAccessIfAsked)
        .task { notificationAccess = await notifier.access() }
        .onChange(of: navigation.requestsScreenRecording) { _, _ in requestAccessIfAsked() }
    }

    @ViewBuilder private var folderRows: some View {
        LabeledContent("Folder") {
            Text(Self.displayPath(of: folderState))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        HStack(spacing: 8) {
            Spacer()
            if folderState != .standard {
                Button("Use Default", action: useDefaultFolder)
            }
            Button("Choose…", action: chooseFolder)
            Button("Show in Finder", action: showFolder)
                .disabled(isFolderUnreachable)
        }
        if isFolderUnreachable {
            warning(Self.unreachableFolderMessage)
                .accessibilityIdentifier("capture.folderUnreachable")
        }
        if let folderError {
            warning(folderError)
                .accessibilityIdentifier("capture.folderError")
        }
    }

    private var isFolderUnreachable: Bool {
        if case .unreachable = folderState { return true }
        return false
    }

    private func warning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Permission is asked for here and nowhere else, like Screen Recording: a prompt from a
    /// capture would land under the overlay.
    private var notificationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: notificationAccess == .allowed ? "checkmark.circle.fill" : "bell.slash")
                    .foregroundStyle(notificationAccess == .allowed ? Color.green : Color.secondary)
                Text(notificationAccess == .allowed ? "Notifications allowed" : "Notifications not allowed")
                    .font(.subheadline)
                Spacer()
                switch notificationAccess {
                case .undetermined:
                    Button("Allow Notifications") {
                        Task { notificationAccess = await notifier.requestAccess() }
                    }
                case .denied:
                    if let url = Self.notificationSettingsURL {
                        Button("Open System Settings") { NSWorkspace.shared.open(url) }
                    }
                case .allowed, nil:
                    EmptyView()
                }
            }
            Text("Each capture sends a notification with a preview. A saved capture's has Show in Finder. The overlay's message shows either way, unless Hide Tool Feedback is on.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("capture.notifications")
    }

    /// Capture and the Redact tool's Pixelate and Blur read the screen, which macOS gates
    /// behind Screen Recording.
    private var screenRecordingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: hasScreenCaptureAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(hasScreenCaptureAccess ? Color.green : Color.orange)
                Text(hasScreenCaptureAccess
                    ? "Screen Recording permission granted"
                    : "Screen Recording permission not granted")
                    .font(.subheadline)
                Spacer()
                if !hasScreenCaptureAccess {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(Self.screenCaptureSettingsURL)
                    }
                }
            }
            Text("Capture Screen, Capture Area, and the Redact tool's Pixelate and Blur styles read the pixels on screen. Until access is granted, capture works only while a fully opaque board is showing, and redactions use a solid fill. macOS may ask you to relaunch Annotate first.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("capture.screenRecording")
    }

    /// Asks for Screen Recording when a capture sent the user here. Asking here, never from
    /// the overlay, keeps the system prompt from opening under the overlay window.
    private func requestAccessIfAsked() {
        guard navigation.requestsScreenRecording else { return }
        navigation.requestsScreenRecording = false
        guard !ScreenSampler.shared.refreshScreenCaptureAccess() else {
            hasScreenCaptureAccess = true
            return
        }
        hasScreenCaptureAccess = ScreenSampler.shared.requestScreenCaptureAccess()
    }

    private func showFolder() {
        folders.withAccess { chosen in
            switch Self.prepareFolder(chosen ?? FileSink.defaultFolder) {
            case .success(let folder):
                folderError = nil
                NSWorkspace.shared.open(folder)
            case .failure(let error):
                folderError = Self.folderErrorMessage(error)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Capture Folder"
        panel.prompt = "Choose"
        panel.message = "Choose where Annotate saves captures."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let folder = panel.url else { return }
            do {
                try folders.choose(folder)
                folderError = nil
            } catch {
                folderError = "Couldn't keep access to that folder. \(error.localizedDescription)"
            }
            folderState = folders.state
        }
        if let window = SettingsWindowManager.shared.settingsWindow ?? NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }

    private func useDefaultFolder() {
        folders.useDefaultFolder()
        folderError = nil
        folderState = folders.state
    }

    /// Creates `folder` if it is missing, so Finder has something to open.
    static func prepareFolder(_ folder: URL) -> Result<URL, Error> {
        Result {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }

    static func folderErrorMessage(_ error: Error) -> String {
        "Couldn't create the folder. \(error.localizedDescription)"
    }
}
