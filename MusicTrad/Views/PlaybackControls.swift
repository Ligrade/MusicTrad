import SwiftUI

/// Précédent / lecture-pause / suivant.
struct PlaybackControls: View {
    @Environment(AppState.self) private var app
    var size: CGFloat = 22

    private var available: Bool { app.track != nil }

    var body: some View {
        HStack(spacing: size * 1.6) {
            button("backward.fill", help: "Précédent", scale: 1) { app.send(.previous) }
            button(app.playback.isPlaying ? "pause.fill" : "play.fill",
                   help: app.playback.isPlaying ? "Pause" : "Lecture", scale: 1.35) { app.send(.playPause) }
            button("forward.fill", help: "Suivant", scale: 1) { app.send(.next) }
        }
        .disabled(!available)
        .opacity(available ? 1 : 0.35)
    }

    private func button(_ symbol: String, help: String, scale: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * scale, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size * 2, height: size * 2)
                .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
