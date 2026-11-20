import SwiftUI

/// Fenêtre toujours au premier plan, redimensionnable, fond semi-transparent.
struct FloatingWindowView: View {
    static let id = "floating-lyrics"

    var body: some View {
        VStack(spacing: 0) {
            TrackHeader()
                .padding(.horizontal, 20)
                .padding(.top, 28)   // place pour les boutons de fenêtre
                .padding(.bottom, 8)
            LyricsView()
            PlaybackControls()
                .padding(.vertical, 14)
        }
        .frame(minWidth: 360, minHeight: 320)
        .containerBackground(LyricsPalette.background, for: .window)
        .background(LyricsPalette.background)
        .preferredColorScheme(.dark)
    }
}
