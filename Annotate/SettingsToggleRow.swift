import SwiftUI

struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    var onChange: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: isOn) { _, _ in
                    onChange?()
                }
        }
    }
}
