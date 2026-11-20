import SwiftUI

/// Écran du mode éco : tout est éteint, un seul bouton au centre pour rallumer.
struct EcoView: View {
    @Environment(AppState.self) private var app
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 18) {
            Button {
                withAnimation(.snappy) { app.setEcoMode(false) }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(Circle().fill(Color.green.opacity(hovering ? 1 : 0.85)))
                    .scaleEffect(hovering ? 1.05 : 1)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
            .help("Réactiver MusicTrad")

            VStack(spacing: 4) {
                Label("Mode éco", systemImage: "leaf.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
                Text("MusicTrad est en veille et ne consomme rien.\nClique pour réactiver.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
