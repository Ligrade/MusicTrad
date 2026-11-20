import SwiftUI

/// En-tête : pochette, titre + étoile, artiste ; à droite, pilules fixes (Réglages/Quitter, langue).
/// Rien ne glisse quand le morceau change : seules la pochette et les textes se fondent.
struct TrackHeader: View {
    @Environment(AppState.self) private var app
    var artworkSize: CGFloat = 64
    /// Boutons Réglages et Quitter en haut à droite (menu de la barre des menus).
    var showsAppButtons = false
    @Environment(\.dismiss) private var dismiss
    @State private var hoveringArtist = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 14) {
                if let t = app.track {
                    // La nouvelle pochette pousse l'ancienne hors du cadre (⏭ par la droite, ⏮ par la gauche).
                    // Seule la pochette s'anime ; le cadre, lui, ne bouge pas.
                    ZStack {
                        ArtworkView(image: app.artwork, size: artworkSize)
                            .id(app.artworkID)
                            .transition(.push(from: app.artworkFromLeading ? .leading : .trailing))
                    }
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(.rect(cornerRadius: artworkSize * 0.14))
                    .shadow(color: .black.opacity(app.playback.isPlaying ? 0.5 : 0.25), radius: 6, y: 3)
                    // En pause : grise et recule légèrement, comme dans Musique.
                    .saturation(app.playback.isPlaying ? 1 : 0)
                    .brightness(app.playback.isPlaying ? 0 : -0.08)
                    .scaleEffect(app.playback.isPlaying ? 1 : 0.86)
                    .animation(.spring(response: 0.45, dampingFraction: 0.72), value: app.playback.isPlaying)
                    .animation(.spring(response: 0.5, dampingFraction: 0.86), value: app.artworkID)
                    .contentShape(.rect)
                    .onTapGesture {
                        if showsAppButtons { dismiss() }   // referme la bulle (pas la fenêtre flottante)
                        app.openAlbum()
                    }
                    .pointerStyle(.link)
                    .help("Ouvrir l'album dans Musique")

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(t.title).font(.title2.bold()).lineLimit(1)
                            FavoriteButton()
                        }
                        Text(t.artist).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                            .underline(hoveringArtist)      // souligné au survol, comme un lien
                            .onHover { hoveringArtist = $0 }
                            .onTapGesture {
                                if showsAppButtons { dismiss() }
                                app.openArtist()
                            }
                            .pointerStyle(.link)
                            .help("Ouvrir la page de l'artiste dans Musique")
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

/// « EN → FR » pour une chanson étrangère. Pour une chanson en français, devient un bouton
/// « FR → EN » qui traduit en anglais seulement au clic (re-clic : on revient sans traduction).
/// Garde toujours sa place pour ne rien décaler.
private struct LanguagePill: View {
    @Environment(AppState.self) private var app
    let language: Locale.Language?

    var body: some View {
        if let language, language.isFrench {
            let active = app.englishRequested
            Button { app.toggleEnglishTranslation() } label: {
                Pill {
                    Label("FR → EN", systemImage: active ? "character.bubble.fill" : "character.bubble")
                        .monospaced()
                        .foregroundStyle(active ? Color.black : Color.primary)
                }
                .background(Capsule().fill(active ? Color.white : .clear))
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .help(active ? "Masquer la traduction anglaise" : "Traduire les paroles en anglais")
            .animation(.snappy, value: active)
        } else {
            Pill {
                Text("\((language?.minimalIdentifier ?? "en").uppercased()) → FR")
                    .monospaced()
            }
            .opacity(language == nil ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: language == nil)
        }
    }
}

/// Mode éco, Réglages et Quitter, dans une pilule.
private struct AppButtons: View {
    @Environment(AppState.self) private var app
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Pill {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) { app.setEcoMode(!app.ecoMode) }
                } label: {
                    Image(systemName: app.ecoMode ? "leaf.fill" : "leaf")
                        .foregroundStyle(app.ecoMode ? Color.green : Color.primary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .help(app.ecoMode ? "Quitter le mode éco" : "Mode éco : met l'app en veille sans la fermer")
                Divider().frame(height: 14)
                Button {
                    dismiss()            // referme la bulle pour qu'elle ne cache pas les Réglages
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
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(LyricsPalette.original)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.14))
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
