import KeyboardShortcuts
import SwiftUI

@main
struct AnnotateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        KeyboardShortcuts.onKeyDown(for: .toggleOverlay) {
            AppDelegate.shared?.toggleOverlay()
        }
        
        KeyboardShortcuts.onKeyDown(for: .toggleAlwaysOnMode) {
            AppDelegate.shared?.toggleAlwaysOnMode()
        }
    }

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            // Route Cmd+, and the app menu's Settings… item to the managed
            // settings window so the scene's own window never appears.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    AppDelegate.shared?.showSettings()
                }
                .keyboardShortcut(",")
            }
        }
    }
}
