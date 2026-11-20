import SwiftUI

struct MenuBarContentView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.floatingWindowEnabled) private var floatingWindowEnabled = false

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
            if floatingWindowEnabled && !app.ecoMode {
                Button {
                    openWindow(id: FloatingWindowView.id)
                    NSApp.activate()
                    dismiss()   // referme la bulle, la fenêtre flottante prend le relais
                } label: { Label("Fenêtre flottante", systemImage: "macwindow.on.rectangle") }
                .buttonStyle(.borderless)
                .font(.title3)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 560)
        .background(LyricsPalette.background)
        .preferredColorScheme(.dark)
        .onAppear { app.viewAppeared() }
        .onDisappear { app.viewDisappeared() }
    }
}
