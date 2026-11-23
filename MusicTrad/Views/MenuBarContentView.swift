import SwiftUI

extension EnvironmentValues {
    /// Vrai dans la bulle de la barre des menus (pour la refermer avant d'ouvrir les Réglages).
    @Entry var inMenuBubble = false
}

struct MenuBarContentView: View {
    @Environment(AppState.self) private var app
    /// Présentation des fonctions, montrée tant que « J'ai compris » n'a pas été cliqué.
    @AppStorage(SettingsKey.onboardingSeen) private var onboardingSeen = false

    var body: some View {
        Group {
            if app.ecoMode {
                // Mode éco : petite fenêtre carrée, la pilule et le bouton pour rallumer.
                VStack(spacing: 0) {
                    HStack { Spacer(); AppButtons() }
                        .padding(14)
                    EcoView()
                }
                .frame(width: 420, height: 420)
            } else if app.bubbleCompact {
                // Bulle repliée : petit lecteur carré.
                MiniPlayerView()
            } else {
                VStack(spacing: 0) {
                    TrackHeader(showsAppButtons: true)
                        .padding(16)
                    Divider()
                    LyricsView()
                        .frame(height: 640)
                        .modifier(FadeInOnAppear())
                    Divider()
                    PlaybackControls()
                        .padding(.vertical, 12)
                }
                .frame(width: 560)
                .overlay {
                    if !onboardingSeen {
                        OnboardingView { withAnimation(.easeOut(duration: 0.25)) { onboardingSeen = true } }
                            .transition(.opacity)
                    }
                }
            }
        }
        .background(WindowResizeAnimator(trigger: app.ecoMode ? 2 : app.bubbleCompact ? 1 : 0,
                                          fixedSize: app.ecoMode ? CGSize(width: 420, height: 420)
                                              : app.bubbleCompact ? CGSize(width: MiniPlayerView.side, height: MiniPlayerView.side) : nil))
        .environment(\.inMenuBubble, true)
        .background { LyricsBackground() }
        .preferredColorScheme(.dark)
        .onAppear { app.viewAppeared() }
        .onDisappear {
            app.viewDisappeared()
            app.libraryOpen = false   // à la réouverture : directement les paroles en direct
        }
    }
}

/// Anime le passage entre la grande bulle et le petit carré du mode éco, en gardant la fenêtre
/// centrée sous l'icône et collée en haut : elle se rétrécit / s'agrandit depuis le centre.
private struct WindowResizeAnimator: NSViewRepresentable {
    let trigger: Int   // 0 bulle complète, 1 repliée, 2 mode éco
    /// Taille connue d'avance (lecteur réduit, mode éco) : pas besoin de la mesurer,
    /// la mesure pouvant encore renvoyer la grande taille juste après le changement.
    let fixedSize: CGSize?

    @MainActor final class Coordinator {
        var lastTrigger: Int?
        /// Dernière taille posée au repos, et point d'ancrage (centre horizontal, bord haut) sous l'icône.
        var stableFrame: NSRect?
        var animating = false
        var generation = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    static func frame(_ size: NSSize, anchorX: CGFloat, top: CGFloat, in window: NSWindow) -> NSRect {
        var target = NSRect(x: (anchorX - size.width / 2).rounded(), y: top - size.height,
                            width: size.width, height: size.height)
        // Reste entière à l'écran (icône près d'un bord).
        if let screen = (window.screen ?? NSScreen.main)?.visibleFrame {
            target.origin.x = min(max(target.minX, screen.minX + 8), screen.maxX - size.width - 8)
        }
        return target
    }

    /// Filet de sécurité : peu après, si le contenu a encore changé de taille, la fenêtre s'y recale.
    static func settle(_ window: NSWindow, anchorX: CGFloat, top: CGFloat, generation: Int, fixed: CGSize?, _ c: Coordinator) {
        // Jusqu'à 2 s : après une longue veille, SwiftUI peut mettre un moment à poser la nouvelle taille.
        for delay in [0.05, 0.2, 0.5, 1, 2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard generation == c.generation, !c.animating, window.isVisible else { return }
                guard let size = fixed ?? contentSize(of: window), size != window.frame.size else { return }
                releaseSizeLimits(of: window)
                let target = frame(size, anchorX: anchorX, top: top, in: window)
                window.setFrame(target, display: true)
                c.stableFrame = target
            }
        }
    }

    /// Taille voulue par le contenu SwiftUI (la fenêtre peut ne pas l'avoir encore prise).
    /// `nil` si la mesure n'est pas exploitable : l'appelant réessaie au lieu de garder l'ancienne taille.
    static func contentSize(of window: NSWindow) -> NSSize? {
        guard let content = window.contentView else { return nil }
        content.layoutSubtreeIfNeeded()
        let fit = content.fittingSize
        return fit.width > 40 && fit.height > 40 ? fit : nil
    }

    /// Les bornes de la fenêtre peuvent encore valoir l'ancienne taille (éco 420) et brider setFrame.
    static func releaseSizeLimits(of window: NSWindow) {
        window.contentMinSize = .zero
        window.contentMaxSize = NSSize(width: 10_000, height: 10_000)
        window.minSize = .zero
        window.maxSize = NSSize(width: 10_000, height: 10_000)
    }

    /// Centre horizontal de l'icône de MusicTrad dans la barre des menus (sur l'écran de la bulle).
    static func statusIconMidX(near frame: NSRect) -> CGFloat? {
        NSApp.windows
            .filter { $0.className.contains("StatusBarWindow") && $0.isVisible }
            .map(\.frame)
            .min { abs($0.midX - frame.midX) < abs($1.midX - frame.midX) }?
            .midX
    }

    func updateNSView(_ view: NSView, context: Context) {
        let c = context.coordinator
        guard let window = view.window else { return }
        defer { c.lastTrigger = trigger }
        guard let previous = c.lastTrigger, previous != trigger, let old = c.stableFrame, window.isVisible else {
            if !c.animating { c.stableFrame = window.frame }
            return
        }
        // Toutes les tailles gardent le même bord haut et se centrent sous l'icône de l'app
        // (à défaut, sur le centre de la taille précédente).
        let anchorX = Self.statusIconMidX(near: old) ?? old.midX, anchorTop = old.maxY
        c.generation += 1
        let generation = c.generation
        let interrupted = c.animating
        // Attend que SwiftUI ait posé la nouvelle taille.
        DispatchQueue.main.async {
            guard generation == c.generation else { return }   // un autre clic est passé entre-temps
            guard let size = fixedSize ?? Self.contentSize(of: window) else {
                // Mesure inutilisable : on ne fige rien, le filet réessaie jusqu'à avoir la bonne taille.
                c.animating = false
                Self.settle(window, anchorX: anchorX, top: anchorTop, generation: generation, fixed: fixedSize, c)
                return
            }
            Self.releaseSizeLimits(of: window)
            let target = Self.frame(size, anchorX: anchorX, top: anchorTop, in: window)
            // Dépliage (repliée → paroles) ou clics rapprochés : on se place directement, sans animation
            // (sinon la fenêtre montre un instant la grande taille ou reste coincée en cours de route).
            // Paroles ↔ lecteur réduit : bascule directe, comme un interrupteur.
            if interrupted || (previous != 2 && trigger != 2) || size == old.size {
                c.animating = false
                window.setFrame(target, display: true)
                c.stableFrame = target
                Self.settle(window, anchorX: anchorX, top: anchorTop, generation: generation, fixed: fixedSize, c)
                return
            }
            c.animating = true
            // Sécurité : si AppKit n'appelle jamais la fin d'animation (fenêtre masquée, veille), on ne reste pas bloqué.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard generation == c.generation, c.animating else { return }
                c.animating = false
                window.setFrame(target, display: true)
                c.stableFrame = target
                Self.settle(window, anchorX: anchorX, top: anchorTop, generation: generation, fixed: fixedSize, c)
            }
            window.setFrame(old, display: false)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                window.animator().setFrame(target, display: true)
            } completionHandler: {
                MainActor.assumeIsolated {
                    guard generation == c.generation else { return }
                    c.animating = false
                    window.setFrame(target, display: true)   // position exacte, même si SwiftUI a bougé entre-temps
                    c.stableFrame = target
                    Self.settle(window, anchorX: anchorX, top: anchorTop, generation: generation, fixed: fixedSize, c)
                }
            }
        }
        // Pendant une animation, l'ancre reste celle du repos précédent.
        c.stableFrame = NSRect(x: anchorX - old.width / 2, y: old.minY, width: old.width, height: old.height)
    }
}

/// Change de disposition (paroles, lecteur réduit, mode éco) sans transition SwiftUI : sinon les deux vues
/// coexistent le temps du fondu, la fenêtre garde la grande taille et le reste devient transparent.
/// C'est la fenêtre qui s'anime (WindowResizeAnimator).
@MainActor func changeBubbleLayout(_ change: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, change)
}

/// Fondu d'apparition (paroles qui reviennent quand on déplie la bulle).
private struct FadeInOnAppear: ViewModifier {
    @State private var visible = false
    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .onAppear { withAnimation(.easeOut(duration: 0.3)) { visible = true } }
    }
}
