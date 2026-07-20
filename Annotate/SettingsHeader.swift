import SwiftUI

/// An SF Symbol inside a colored, gradient-filled rounded square, shared by
/// the settings sidebar and section headers.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(color.gradient)
            )
    }
}

/// System Settings style section header: an SF Symbol inside a colored
/// rounded square, next to a title with a secondary subtitle.
struct SettingsHeader: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 8) {
            IconTile(symbol: icon, color: color, size: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
