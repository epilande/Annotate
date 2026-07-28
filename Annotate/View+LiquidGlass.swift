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
}
