import SwiftUI

struct ToolsSettingsView: View {
    @AppStorage(UserDefaults.defaultTextFontSizeKey)
    private var defaultTextSize: Double = Double(defaultTextAnnotationFontSize)
    @AppStorage(UserDefaults.textBackgroundKey)
    private var textBackgroundEnabled = false
    @AppStorage(UserDefaults.defaultCounterFontSizeKey)
    private var defaultCounterSize: Double = Double(defaultCounterFontSize)
    @AppStorage(UserDefaults.redactionStyleKey)
    private var redactionStyle: RectangleStyle = UserDefaults.redactionStyleDefault
    @State private var hasScreenCaptureAccess = ScreenSampler.shared.hasScreenCaptureAccess

    /// The Redact tool's fills. `.outline` is the plain Rectangle tool, not a redaction.
    static let redactionStyles = RectangleStyle.allCases.filter { $0 != .outline }

    static let screenCaptureSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    var body: some View {
        let minTextSize = Double(textAnnotationFontSizeRange.lowerBound)
        let maxTextSize = Double(textAnnotationFontSizeRange.upperBound)
        let minCounterSize = Double(counterFontSizeRange.lowerBound)
        let maxCounterSize = Double(counterFontSizeRange.upperBound)
        Form {
            Section {
                PaneHeader(pane: .tools)
            }

            Section {
                SettingsSliderRow(
                    title: "Default Text Size",
                    value: $defaultTextSize,
                    range: minTextSize...maxTextSize,
                    step: 1,
                    valueText: { "\(Int($0)) pt" },
                    boundsText: { "\(Int($0)) pt" }
                )
                Toggle("Label background", isOn: $textBackgroundEnabled)
            } header: {
                SettingsHeader(
                    icon: "textformat.size",
                    color: .orange,
                    title: "Text Tool",
                    subtitle: "Adjust the default font size for text annotations"
                )
            }

            Section {
                SettingsSliderRow(
                    title: "Default Counter Size",
                    value: $defaultCounterSize,
                    range: minCounterSize...maxCounterSize,
                    step: 1,
                    valueText: { "\(Int($0)) pt" },
                    boundsText: { "\(Int($0)) pt" }
                )
            } header: {
                SettingsHeader(
                    icon: "number.circle",
                    color: .green,
                    title: "Counter Tool",
                    subtitle: "Adjust the default size for counter annotations"
                )
            }

            Section {
                Picker("Style", selection: $redactionStyle) {
                    ForEach(Self.redactionStyles, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Text("Use Solid for passwords and other secrets. Pixelate and Blur keep the rough shape of the content, which can sometimes be partly recovered.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if redactionStyle != .solid {
                    screenRecordingRow
                }
            } header: {
                SettingsHeader(
                    icon: "eye.slash",
                    color: .gray,
                    title: "Redact Tool",
                    subtitle: "Choose how redaction rectangles hide what is under them"
                )
            }
        }
        .formStyle(.grouped)
        .settingsScrollEdgeEffect()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user comes back here after flipping the switch in System Settings.
            hasScreenCaptureAccess = ScreenSampler.shared.refreshScreenCaptureAccess()
        }
        .onChange(of: redactionStyle) { _, style in
            // Ask here, never from the overlay: the system prompt sits below the fullscreen
            // overlay window, so from there the user would never see it.
            guard style != .solid, !ScreenSampler.shared.refreshScreenCaptureAccess() else { return }
            hasScreenCaptureAccess = ScreenSampler.shared.requestScreenCaptureAccess()
        }
    }

    /// Pixelate and Blur read the screen under the rectangle, which macOS gates behind
    /// Screen Recording. Until it is granted the tool falls back to a solid black fill.
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
            Text("Pixelate and Blur need Screen Recording access to read the pixels under the rectangle. Redactions use solid black until it is granted, and macOS may ask you to relaunch Annotate first.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("tools.redact.screenRecording")
    }
}
