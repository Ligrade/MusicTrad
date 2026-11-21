import SwiftUI

struct MenuBarContentView: View {
    @Environment(AppState.self) private var app

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
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                VStack(spacing: 0) {
                    TrackHeader(showsAppButtons: true)
                        .padding(16)
                    Divider()
                    LyricsView()
                        .frame(height: 640)
                    Divider()
                    PlaybackControls()
                        .padding(.vertical, 12)
                }
                .frame(width: 560)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .background(WindowResizeAnimator(trigger: app.ecoMode))
        .background(LyricsPalette.background)
        .preferredColorScheme(.dark)
        .onAppear { app.viewAppeared() }
        .onDisappear { app.viewDisappeared() }
    }
}

/// Anime le passage entre la grande bulle et le petit carré du mode éco, en gardant la fenêtre
/// centrée sous l'icône et collée en haut : elle se rétrécit / s'agrandit depuis le centre.
private struct WindowResizeAnimator: NSViewRepresentable {
    let trigger: Bool   // mode éco

    @MainActor final class Coordinator {
        var lastTrigger: Bool?
        var stableFrame: NSRect?
        var animating = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let c = context.coordinator
        guard let window = view.window else { return }
        defer { c.lastTrigger = trigger }
        guard let previous = c.lastTrigger, previous != trigger,
              let old = c.stableFrame, window.isVisible, !c.animating else {
            if !c.animating { c.stableFrame = window.frame }
            return
        }
        // Attend que SwiftUI ait posé la nouvelle taille, puis anime depuis l'ancienne,
        // même centre horizontal et même bord haut.
        DispatchQueue.main.async {
            let size = window.frame.size
            guard size != old.size else { return }
            let target = NSRect(x: (old.midX - size.width / 2).rounded(), y: old.maxY - size.height,
                                width: size.width, height: size.height)
            c.animating = true
            window.setFrame(old, display: false)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                window.animator().setFrame(target, display: true)
            } completionHandler: {
                MainActor.assumeIsolated {
                    c.animating = false
                    c.stableFrame = window.frame
                }
            }
        }
    }
}
