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
                SettingsSliderRow(
                    title: "Default Text Size",
                    value: $defaultTextSize,
                    range: minTextSize...maxTextSize,
                    step: 1,
                    valueText: { "\(Int($0)) pt" },
                    boundsText: { "\(Int($0)) pt" }
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
        }
        .formStyle(.grouped)
        .settingsScrollEdgeEffect()
    }
}
