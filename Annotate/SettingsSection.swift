import SwiftUI

struct SettingsSection<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(
                icon: icon,
                title: title,
                subtitle: subtitle
            )

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(.leading, 48)
        }
    }
}
