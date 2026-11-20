import SwiftUI

@main
struct MusicTradApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(appState)
        } label: {
            // Feuille en mode éco, bulle de paroles sinon.
            Image(systemName: appState.ecoMode ? "leaf" : "quote.bubble")
        }
        .menuBarExtraStyle(.window)

        Window("Paroles", id: FloatingWindowView.id) {
            FloatingWindowView()
                .environment(appState)
        }
        .windowLevel(.floating)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 640, height: 820)
        .defaultLaunchBehavior(Preferences.openWindowAtLaunch ? .presented : .suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
