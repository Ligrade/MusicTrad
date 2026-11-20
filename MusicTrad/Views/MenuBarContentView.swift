import SwiftUI

struct MenuBarContentView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.floatingWindowEnabled) private var floatingWindowEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            TrackHeader(showsAppButtons: true)
                .padding(16)
            Divider()
            LyricsView()
                .frame(height: 640)
            Divider()
            PlaybackControls()
                .padding(.vertical, 12)
            if floatingWindowEnabled {
                Button {
                    openWindow(id: FloatingWindowView.id)
                    NSApp.activate()
                } label: { Label("Fenêtre flottante", systemImage: "macwindow.on.rectangle") }
                .buttonStyle(.borderless)
                .font(.title3)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 560)
        .background(LyricsPalette.background)
        .preferredColorScheme(.dark)
    }
}
