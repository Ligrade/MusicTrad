import SwiftUI

/// Sortie audio de Musique (Mac, enceintes AirPlay, Apple TV…), en bas à gauche.
struct AirPlayButton: View {
    @Environment(AppState.self) private var app
    @State private var showDevices = false

    var body: some View {
        Button { showDevices.toggle() } label: {
            Image(systemName: "airplay.audio")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(app.airPlayActive ? Color.accentColor : .white)
                .frame(width: 34, height: 34)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Sortie audio (AirPlay)")
        .onAppear { app.refreshAirPlay() }
        .popover(isPresented: $showDevices, arrowEdge: .top) {
            AirPlayList().environment(app)
        }
    }
}

private struct AirPlayList: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sortie audio").font(.headline).padding(.bottom, 6)
            if app.airPlayDevices.isEmpty {
                Text("Aucune sortie trouvée. Musique est-elle ouverte ?")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(app.airPlayDevices) { device in
                HStack(spacing: 10) {
                    Button { app.selectAirPlay(device) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: device.symbol)
                                .font(.system(size: 16))
                                .frame(width: 24)
                                .foregroundStyle(device.selected ? Color.accentColor : .secondary)
                            Text(device.name).lineLimit(1)
                            Spacer(minLength: 8)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    // Rond à droite : ajouter / retirer du groupe (plusieurs sorties à la fois).
                    Button { app.selectAirPlay(device, addToGroup: true) } label: {
                        Image(systemName: device.selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(device.selected ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(device.selected ? "Retirer de la lecture" : "Ajouter à la lecture")
                }
                .padding(.vertical, 6)
                .opacity(device.available ? 1 : 0.4)
                .disabled(!device.available)
            }
            Text("Clic sur un nom : seule sortie · rond : en plus des autres")
                .font(.caption).foregroundStyle(.tertiary).padding(.top, 6)
        }
        .padding(16)
        .frame(width: 300)
        .preferredColorScheme(.dark)
        .onAppear { app.refreshAirPlay() }
    }
}
