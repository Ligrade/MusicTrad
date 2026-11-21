import AppKit
import SwiftUI

@main
struct MusicTradApp: App {
    @State private var appState: AppState

    init() {
        let state = AppState()
        _appState = State(initialValue: state)
        StatusItemMenu.shared.install(state)
    }

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

/// Clic droit (ou ctrl-clic) sur l'icône de la barre des menus : petit menu
/// « Paroles + traduction » (coché quand les paroles sont affichées), Réglages, Quitter.
@MainActor final class StatusItemMenu: NSObject {
    static let shared = StatusItemMenu()
    private weak var app: AppState?
    private var monitor: Any?

    func install(_ app: AppState) {
        self.app = app
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, let window = event.window, window.className.contains("StatusBarWindow"),
                  event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return event }
            self.show(in: window)
            return nil   // la bulle ne s'ouvre pas
        }
    }

    private func show(in window: NSWindow) {
        guard let app, let view = window.contentView else { return }
        let menu = NSMenu()
        let lyrics = NSMenuItem(title: "Paroles + traduction", action: #selector(toggleLyrics), keyEquivalent: "")
        lyrics.state = app.showsLyrics ? .on : .off
        lyrics.target = self
        menu.addItem(lyrics)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quitter MusicTrad", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        let y = view.isFlipped ? view.bounds.maxY + 6 : view.bounds.minY - 6
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: y), in: view)
    }

    /// Paroles + traduction : quitte le lecteur (ou le mode éco) et traduit tout de suite.
    /// Déjà sur les paroles : traduit seulement.
    @objc private func toggleLyrics() { app?.showLyricsAndTranslate() }

    /// Ouvre la fenêtre Réglages via l'élément « Réglages… » du menu de l'app (créé par SwiftUI).
    @objc private func openSettings() {
        NSApp.activate()
        for top in NSApp.mainMenu?.items ?? [] {
            guard let submenu = top.submenu,
                  let index = submenu.items.firstIndex(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command })
            else { continue }
            submenu.performActionForItem(at: index)
            return
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
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
