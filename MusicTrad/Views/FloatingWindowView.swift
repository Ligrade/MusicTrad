import SwiftUI

/// Fenêtre toujours au premier plan, redimensionnable, fond semi-transparent.
struct FloatingWindowView: View {
    static let id = "floating-lyrics"
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TrackHeader()
                .padding(.horizontal, 20)
                .padding(.top, 28)   // place pour les boutons de fenêtre
                .padding(.bottom, 8)
            if app.ecoMode {
                EcoView()
            } else {
                LyricsView()
                PlaybackControls()
                    .padding(.vertical, 14)
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .containerBackground(LyricsPalette.background, for: .window)
        .background { LyricsBackground() }
        .preferredColorScheme(.dark)
        .onAppear { app.viewAppeared() }
        .onDisappear { app.viewDisappeared() }
    }
}
