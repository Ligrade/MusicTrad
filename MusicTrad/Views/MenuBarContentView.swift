import SwiftUI

struct MenuBarContentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TrackHeader(showsAppButtons: true)
                .padding(16)
            Divider()
            if app.ecoMode {
                EcoView().frame(height: 320)
            } else {
            LyricsView()
                .frame(height: 640)
            Divider()
            PlaybackControls()
                .padding(.vertical, 12)
            }
        }
        .frame(width: 560)
        .background(LyricsPalette.background)
        .preferredColorScheme(.dark)
        .onAppear { app.viewAppeared() }
        .onDisappear { app.viewDisappeared() }
    }
}
