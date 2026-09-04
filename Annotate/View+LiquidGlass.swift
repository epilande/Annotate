import SwiftUI

extension View {
    /// Applies a soft scroll edge effect on macOS 26 (Liquid Glass) so
    /// scrollable settings content blends into the window chrome.
    /// No-op on earlier systems.
    @ViewBuilder
    func settingsScrollEdgeEffect() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }

    /// Uses the Liquid Glass button style on macOS 26, falling back to the
    /// standard bordered style on earlier systems.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Gives an overlay toolbar segment a Liquid Glass background on macOS 26,
    /// falling back to an ultra-thin material with a hairline rim on earlier systems.
    @ViewBuilder
    func toolbarGlassSegment(cornerRadius: CGFloat = 18) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.32), .white.opacity(0.09)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        }
    }
}
