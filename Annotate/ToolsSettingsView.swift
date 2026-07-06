import SwiftUI

struct ToolsSettingsView: View {
    @AppStorage(UserDefaults.defaultTextFontSizeKey)
    private var defaultTextSize: Double = Double(defaultTextAnnotationFontSize)
    @AppStorage(UserDefaults.defaultCounterFontSizeKey)
    private var defaultCounterSize: Double = Double(defaultCounterFontSize)

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
                DefaultSizeSliderRow(
                    title: "Default Text Size",
                    size: $defaultTextSize,
                    range: minTextSize...maxTextSize
                )
            } header: {
                SettingsHeader(
                    icon: "textformat.size",
                    color: .orange,
                    title: "Text Tool",
                    subtitle: "Adjust the default font size for text annotations"
                )
            }

            Section {
                DefaultSizeSliderRow(
                    title: "Default Counter Size",
                    size: $defaultCounterSize,
                    range: minCounterSize...maxCounterSize
                )
            } header: {
                SettingsHeader(
                    icon: "number.circle",
                    color: .green,
                    title: "Counter Tool",
                    subtitle: "Adjust the default size for counter annotations"
                )
            }
        }
        .formStyle(.grouped)
        .settingsScrollEdgeEffect()
    }
}

private struct DefaultSizeSliderRow: View {
    let title: String
    @Binding var size: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent {
            Slider(value: $size, in: range, step: 1) {
            } minimumValueLabel: {
                Text("\(Int(range.lowerBound)) pt")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("\(Int(range.upperBound)) pt")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(title)
            Text("\(Int(size)) pt")
                .monospacedDigit()
        }
    }
}
