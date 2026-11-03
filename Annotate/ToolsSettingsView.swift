import SwiftUI

struct ToolsSettingsView: View {
    @AppStorage(.textFontSize)
    private var defaultTextSize: Double
    @AppStorage(.textBackground)
    private var textBackgroundEnabled: Bool
    @AppStorage(.counterFontSize)
    private var defaultCounterSize: Double
    @AppStorage(.counterStyle)
    private var counterStyle: CounterStyle
    @AppStorage(.redactionStyle)
    private var redactionStyle: RectangleStyle
    /// Switches the settings window to the Capture pane, which shows Screen Recording status.
    var showCapturePane: (() -> Void)?

    /// The Redact tool's fills. `.outline` is the plain Rectangle tool, not a redaction.
    static let redactionStyles = RectangleStyle.allCases.filter { $0 != .outline }

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
                Picker("Style", selection: $counterStyle) {
                    ForEach(CounterStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Text(counterStyle == .bordered
                    ? "A circle outlined in the selected color with the number in that color."
                    : "A circle filled with the selected color with a white number, or a black one on light colors.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                SettingsHeader(
                    icon: "number.circle",
                    color: .green,
                    title: "Counter Tool",
                    subtitle: "Adjust the default size and style for counter annotations"
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
                    screenRecordingPointer
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
        .onChange(of: redactionStyle) { _, style in
            // Ask here, never from the overlay: the system prompt sits below the fullscreen
            // overlay window, so from there the user would never see it.
            guard style != .solid, !ScreenSampler.shared.refreshScreenCaptureAccess() else { return }
            ScreenSampler.shared.requestScreenCaptureAccess()
        }
    }

    /// Pixelate and Blur read the screen under the rectangle, which macOS gates behind
    /// Screen Recording. Its status lives in the Capture pane, which Capture Screen shares.
    private var screenRecordingPointer: some View {
        HStack(spacing: 6) {
            Text("Pixelate and Blur need Screen Recording access and use a solid fill until it is granted. Check its status in Capture.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let showCapturePane {
                Button("Show Capture Settings", action: showCapturePane)
            }
        }
        .accessibilityIdentifier("tools.redact.screenRecording")
    }
}
