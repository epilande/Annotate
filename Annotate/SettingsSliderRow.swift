import SwiftUI

/// A labeled slider row for the settings panes: a title with an optional
/// live value line, and secondary labels for the range bounds.
struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var valueText: ((Double) -> String)? = nil
    let boundsText: (Double) -> String

    var body: some View {
        LabeledContent {
            if let step {
                Slider(value: $value, in: range, step: step) {
                } minimumValueLabel: {
                    boundsLabel(range.lowerBound)
                } maximumValueLabel: {
                    boundsLabel(range.upperBound)
                }
            } else {
                Slider(value: $value, in: range) {
                } minimumValueLabel: {
                    boundsLabel(range.lowerBound)
                } maximumValueLabel: {
                    boundsLabel(range.upperBound)
                }
            }
        } label: {
            Text(title)
            if let valueText {
                Text(valueText(value))
                    .monospacedDigit()
            }
        }
    }

    private func boundsLabel(_ bound: Double) -> some View {
        Text(boundsText(bound))
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
