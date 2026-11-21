import AppKit
import SwiftUI

@main
struct MusicTradApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(appState)
        } label: {
            // Bulle de paroles ; en mode éco, une petite feuille vient se poser devant.
            if appState.ecoMode { Image(nsImage: .ecoMenuBarIcon) } else { Image(systemName: "quote.bubble") }
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

extension NSImage {
    /// Icône de la barre des menus en mode éco : la bulle de MusicTrad, une feuille posée en bas à droite.
    static let ecoMenuBarIcon: NSImage = {
        let size = NSSize(width: 20, height: 16)
        let bubble = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))!
        let leaf = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Mode éco")!
            .withSymbolConfiguration(.init(pointSize: 6.5, weight: .bold))!
        let image = NSImage(size: size, flipped: false) { _ in
            bubble.draw(in: NSRect(x: 0, y: 16 - bubble.size.height, width: bubble.size.width, height: bubble.size.height))
            let leafRect = NSRect(x: 20 - leaf.size.width, y: 0, width: leaf.size.width, height: leaf.size.height)
            // Détoure la feuille pour qu'elle se détache de la bulle.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: leafRect.insetBy(dx: -1, dy: -1)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            leaf.draw(in: leafRect)
            return true
        }
        image.isTemplate = true
        return image
    }()
}
