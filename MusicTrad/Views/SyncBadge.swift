import SwiftUI

/// Petit voyant de synchro à droite des commandes ; au clic, le détail et les réglages du morceau.
struct SyncBadge: View {
    @Environment(AppState.self) private var app
    @State private var showDetails = false

    /// Morceau sans paroles (instrumental ou introuvable) : badge grisé, non cliquable.
    private var noLyrics: Bool {
        guard app.track != nil else { return false }
        switch app.lyricsStatus {
        case .notFound: return true
        case .loaded(let l): return l.isInstrumental
        default: return false
        }
    }

    var body: some View {
        let check = app.syncCheck
        Button { showDetails.toggle() } label: {
            Image(systemName: check.map(Self.symbol) ?? "checkmark.seal.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(check.map(Self.color) ?? Color.gray)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(check != nil ? 1 : noLyrics ? 0.35 : 0)
        .disabled(check == nil)
        .help(noLyrics ? "Pas de paroles pour ce morceau" : "Vérifier la synchronisation des paroles")
        .popover(isPresented: $showDetails, arrowEdge: .top) {
            SyncDetails(isPresented: $showDetails).environment(app)
        }
    }

    static func symbol(_ c: SyncCheck) -> String {
        switch c {
        case .synced: "checkmark.seal.fill"
        case .tooLong, .endsEarly: "exclamationmark.triangle.fill"
        case .unsynced: "text.alignleft"
        }
    }

    static func color(_ c: SyncCheck) -> Color {
        switch c {
        case .synced: .green
        case .tooLong, .endsEarly: .orange
        case .unsynced: .secondary
        }
    }
}

private struct SyncDetails: View {
    @Environment(AppState.self) private var app
    @Binding var isPresented: Bool

    var body: some View {
        let check = app.syncCheck ?? .unsynced
        VStack(alignment: .leading, spacing: 14) {
            Label(title(check), systemImage: SyncBadge.symbol(check))
                .font(.headline)
                .foregroundStyle(SyncBadge.color(check))
            Text(detail(check))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let source = app.lyrics?.source {
                Text("Source : \(source)").font(.caption).foregroundStyle(.tertiary)
            }

            if check != .unsynced {
                Divider()
                Button {
                    app.startCalibration()
                    isPresented = false
                } label: {
                    Label("Recaler sur ce que j'entends", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .help("Clique ensuite sur la ligne chantée en ce moment : tout le morceau se cale dessus.")
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Décalage pour ce morceau").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "%+.1f s", app.songOffset)).monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Button { app.setSongOffset(app.songOffset - 0.5) } label: { Image(systemName: "minus") }
                        Slider(value: Binding(get: { app.songOffset }, set: { app.setSongOffset($0) }),
                               in: -5...5, step: 0.1)
                        Button { app.setSongOffset(app.songOffset + 0.5) } label: { Image(systemName: "plus") }
                    }
                    HStack {
                        Text("+ : paroles plus tôt · − : plus tard").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Rétablir") { app.setSongOffset(0) }
                            .controlSize(.small)
                            .disabled(app.songOffset == 0)
                    }
                }
            }

            Divider()
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button {
                        app.tryOtherVersion()
                    } label: {
                        Label("Autre version / source", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(app.searchingVersion)
                    if app.searchingVersion { ProgressView().controlSize(.small) }
                }
                if let info = app.versionInfo {
                    Text("Version \(info.index) sur \(info.count)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(width: 340)
        .preferredColorScheme(.dark)
    }

    private func title(_ c: SyncCheck) -> String {
        switch c {
        case .synced: "Paroles synchronisées"
        case .tooLong, .endsEarly: "Synchro douteuse"
        case .unsynced: "Paroles non synchronisées"
        }
    }

    private func detail(_ c: SyncCheck) -> String {
        switch c {
        case .synced:
            "Le timing correspond à la durée du morceau. Si c'est quand même décalé : recale sur ce que tu entends, ajuste le décalage, ou essaie une autre version ou source (LRCLIB, NetEase)."
        case .tooLong:
            "Ces paroles durent plus longtemps que le morceau : elles viennent sans doute d'une autre version (album, radio, live)."
        case .endsEarly:
            "Les paroles s'arrêtent bien avant la fin du morceau : elles viennent sans doute d'une version plus courte."
        case .unsynced:
            "Seul le texte brut est disponible pour cette version : pas de défilement automatique. Essaie une autre version."
        }
    }
}
