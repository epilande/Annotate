import SwiftUI

struct CaptureSettingsView: View {
    var navigation: SettingsNavigation
    @State private var hasScreenCaptureAccess = ScreenSampler.shared.hasScreenCaptureAccess

    static let screenCaptureSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    init(navigation: SettingsNavigation = SettingsNavigation()) {
        self.navigation = navigation
    }

    /// The capture folder with the home folder shown as `~`.
    static var folderDisplayPath: String {
        let folder = FileSink.defaultFolder.path
        let home = FileSink.realHomeDirectory.path
        guard folder.hasPrefix(home + "/") else { return folder }
        return "~" + folder.dropFirst(home.count)
    }

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .capture)
            }

            Section {
                LabeledContent("Folder") {
                    HStack(spacing: 8) {
                        Text(Self.folderDisplayPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Button("Show in Finder", action: showFolder)
                    }
                }
                Text("Capture Screen saves a PNG of the display, with the board and annotations as they appear, to this folder and copies it to the clipboard.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                SettingsHeader(
                    icon: "camera.viewfinder",
                    color: .teal,
                    title: "Capture Screen",
                    subtitle: "Save the display with its annotations"
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
        }
        .onAppear(perform: requestAccessIfAsked)
        .onChange(of: navigation.requestsScreenRecording) { _, _ in requestAccessIfAsked() }
    }

    /// Capture Screen and the Redact tool's Pixelate and Blur read the screen, which macOS
    /// gates behind Screen Recording.
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
            Text("Capture Screen and the Redact tool's Pixelate and Blur styles read the pixels on screen. Until access is granted, Capture Screen works only while a fully opaque board is showing, and redactions use a solid fill. macOS may ask you to relaunch Annotate first.")
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
        let folder = FileSink.defaultFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
