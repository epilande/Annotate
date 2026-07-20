import Combine
import SwiftUI

struct BoardSettingsView: View {
    @AppStorage(UserDefaults.enableBoardKey)
    private var enableBoard = false
    @State private var boardOpacity: Double = BoardManager.shared.opacity

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .board)
            }

            Section {
                Toggle(isOn: $enableBoard) {
                    Text("Enable Board")
                    Text("Show whiteboard or blackboard background")
                }
                .onChange(of: enableBoard) { _, _ in
                    BoardManager.shared.isEnabled = enableBoard
                }

                SettingsSliderRow(
                    title: "Board Opacity",
                    value: $boardOpacity,
                    range: 0.1...1.0,
                    boundsText: { "\(Int($0 * 100))%" }
                )
                .onChange(of: boardOpacity) { _, newValue in
                    BoardManager.shared.opacity = newValue
                }
            } header: {
                SettingsHeader(
                    icon: "rectangle.inset.filled",
                    color: .indigo,
                    title: "Board Settings",
                    subtitle: "Customize board appearance and visibility"
                )
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .settingsScrollEdgeEffect()
        .onAppear {
            syncState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .boardStateChanged)) { _ in
            syncState()
        }
    }

    private func syncState() {
        enableBoard = BoardManager.shared.isEnabled
        boardOpacity = BoardManager.shared.opacity
    }
}
