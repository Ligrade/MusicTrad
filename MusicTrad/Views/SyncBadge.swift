import SwiftUI

/// Petit voyant de synchro à droite des commandes ; au clic, le détail et les réglages du morceau.
struct SyncBadge: View {
    @Environment(AppState.self) private var app
    @State private var showDetails = false

    var body: some View {
        let check = app.syncCheck
        Button { showDetails.toggle() } label: {
            Image(systemName: check.map(Self.symbol) ?? "checkmark.seal.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(check.map(Self.color) ?? .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(check == nil ? 0 : 1)
        .disabled(check == nil)
        .help("Vérifier la synchronisation des paroles")
        .popover(isPresented: $showDetails, arrowEdge: .top) {
            SyncDetails().environment(app)
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

            if check != .unsynced {
                Divider()
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
            HStack {
                Button {
                    app.tryOtherVersion()
                } label: {
                    Label("Essayer une autre version", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(app.searchingVersion)
                if app.searchingVersion { ProgressView().controlSize(.small) }
                Spacer()
                if let info = app.versionInfo {
                    Text("\(info.index) / \(info.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
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
            "Le timing des paroles correspond à la durée du morceau. Si c'est quand même décalé, ajuste ci-dessous ou essaie une autre version."
        case .tooLong:
            "Ces paroles durent plus longtemps que le morceau : elles viennent sans doute d'une autre version (album, radio, live)."
        case .endsEarly:
            "Les paroles s'arrêtent bien avant la fin du morceau : elles viennent sans doute d'une version plus courte."
        case .unsynced:
            "Seul le texte brut est disponible pour cette version : pas de défilement automatique. Essaie une autre version."
        }
    }
}
