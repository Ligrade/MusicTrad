import SwiftUI

/// En-tête : pochette, titre + étoile, artiste ; à droite, pilules fixes (Réglages/Quitter, langue).
/// Rien ne glisse quand le morceau change : seules la pochette et les textes se fondent.
struct TrackHeader: View {
    @Environment(AppState.self) private var app
    var artworkSize: CGFloat = 64
    /// Boutons Réglages et Quitter en haut à droite (menu de la barre des menus).
    var showsAppButtons = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 14) {
                if let t = app.track {
                    // Fondu de la pochette dans un cadre de taille fixe : aucun déplacement.
                    ZStack {
                        ArtworkView(image: app.artwork, size: artworkSize)
                            .id(t.id)
                            .transition(.opacity)
                    }
                    .frame(width: artworkSize, height: artworkSize)
                    .animation(.easeInOut(duration: 0.3), value: t.id)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(t.title).font(.title2.bold()).lineLimit(1)
                            FavoriteButton()
                        }
                        Text(t.artist).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(height: artworkSize)
                }
                Spacer(minLength: 0)
                // Colonne de droite ancrée en haut : les pilules ne bougent jamais.
                VStack(alignment: .trailing, spacing: 8) {
                    if showsAppButtons { AppButtons() }
                    LanguagePill(language: app.track == nil ? nil : app.sourceLanguage)
                }
            }
            if let error = app.favoriteError {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
        }
        .transaction { $0.animation = nil }   // pas d'animation de mise en page héritée
    }
}

/// Pilule commune (même hauteur pour les boutons et la langue).
private struct Pill<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .font(.callout)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.quaternary, in: .capsule)
    }
}

/// « EN → FR » ; garde sa place même vide pour ne pas décaler le reste.
private struct LanguagePill: View {
    let language: Locale.Language?

    private var visible: Bool { language.map { !$0.isFrench } ?? false }

    var body: some View {
        Pill {
            Text("\((language?.minimalIdentifier ?? "en").uppercased()) → FR")
                .monospaced()
        }
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: visible)
    }
}

/// Réglages et Quitter, dans une pilule.
private struct AppButtons: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Pill {
            HStack(spacing: 12) {
                Button {
                    openSettings()
                    NSApp.activate()
                } label: { Image(systemName: "gearshape") }
                .help("Réglages")
                Divider().frame(height: 14)
                Button {
                    NSApp.terminate(nil)
                } label: { Image(systemName: "power") }
                .help("Quitter MusicTrad")
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.14).fill(Color.white.opacity(0.08))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(LyricsPalette.original)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.14))
        .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
        .animation(.easeInOut(duration: 0.3), value: image != nil)
    }
}

/// Étoile blanche vide ; jaune quand le morceau est dans les favoris de Musique.
/// Elle ne s'anime qu'au clic, pas quand on passe à un morceau déjà en favori.
private struct FavoriteButton: View {
    @Environment(AppState.self) private var app
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            withAnimation(.snappy) { app.toggleFavorite() }
        } label: {
            Image(systemName: app.isFavorited ? "star.fill" : "star")
                .font(.title3.weight(.semibold))
                .foregroundStyle(app.isFavorited ? Color.yellow : Color.white)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: taps)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .id(app.track?.id)   // nouveau morceau = nouvelle étoile, sans transition
        .help(app.isFavorited ? "Retirer des titres favoris" : "Ajouter aux titres favoris")
    }
}
