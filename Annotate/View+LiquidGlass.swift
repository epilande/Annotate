import SwiftUI

/// The segment supplies the refractive glass. This lens adds relief within that
/// surface without nesting another glass effect, which can obscure chip content.
struct ToolbarSelectionLens: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(colorScheme == .dark ? 0.25 : 0.6), location: 0),
                        .init(color: .white.opacity(0.10), location: 0.48),
                        .init(color: .black.opacity(0.06), location: 0.75),
                        .init(color: .white.opacity(0.16), location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                }
            }
            .overlay {
                shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.6 : 0.16), lineWidth: 1)
            }
            .overlay {
                shape.inset(by: 0.5).strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.65), location: 0),
                            .init(color: .white.opacity(0.08), location: 0.5),
                            .init(color: .white.opacity(0.3), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
            }
            .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

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
