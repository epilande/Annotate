import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Custom Tab Bar
            HStack(spacing: 0) {
                CustomTabButton(
                    icon: "gearshape",
                    label: "General",
                    isSelected: selectedTab == 0
                ) {
                    selectedTab = 0
                }

                CustomTabButton(
                    icon: "keyboard",
                    label: "Shortcuts",
                    isSelected: selectedTab == 1
                ) {
                    selectedTab = 1
                }
            }
            .frame(height: 60)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content Area
            Group {
                if selectedTab == 0 {
                    GeneralSettingsView()
                } else {
                    ShortcutsSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Done Button
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 600, height: 600)
    }
}

struct CustomTabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? .blue : .secondary)

                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}
