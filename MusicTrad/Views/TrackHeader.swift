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
                            LyricsFavoriteButton()
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
                    HStack(spacing: 8) {
                        LanguagePill(language: app.track == nil ? nil : app.sourceLanguage)
                        LibraryPill()
                    }
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

/// « EN → FR » pour une chanson étrangère : un clic coupe la traduction (pilule barrée), un autre la relance.
/// Rien pour une chanson en français.
private struct LanguagePill: View {
    @Environment(AppState.self) private var app
    @AppStorage(SettingsKey.autoTranslate) private var autoTranslate = false
    let language: Locale.Language?
    @State private var pulsing = false

    /// Clignote doucement tant que la traduction est en cours.
    private var translating: Bool {
        switch app.translationStatus {
        case .translating, .partial: true
        default: false
        }
    }

    var body: some View {
        pill
            .opacity(pulsing ? 0.35 : 1)
            .animation(pulsing ? .easeInOut(duration: 0.7).repeatForever() : .easeOut(duration: 0.3), value: pulsing)
            .onAppear { pulsing = translating && app.isOnScreen }
            .onChange(of: translating && app.isOnScreen) { _, now in pulsing = now }
            .help(translating ? "Traduction en cours…" : "")
    }

    @ViewBuilder
    private var pill: some View {
        if let language, language.isFrench {
            // Chanson en français : pas de pilule (la traduction en anglais se règle dans les Réglages).
            EmptyView()
        } else {
            // Pas encore traduit : un clic traduit. Traduit : un clic barre (original seul), un autre réaffiche.
            let hidden = app.translationHidden
            let shown = app.translationShown
            Button { app.languagePillTapped() } label: {
                Pill {
                    HStack(spacing: 5) {
                        // ∞ : traduction automatique activée (clic droit sur la pilule pour basculer).
                        if autoTranslate {
                            Image(systemName: "infinity")
                                .font(.caption.weight(.bold))
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text("\(language?.pillCode ?? "EN") → FR")
                            .monospaced()
                            .strikethrough(hidden)
                    }
                    // vert pendant la traduction ; estompé tant que rien n'est traduit ou quand c'est barré
                    .foregroundStyle(translating ? Color.green : shown ? Color.primary : Color.secondary)
                }
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .overlay(RightClickCatcher {
                withAnimation(.snappy) { autoTranslate.toggle() }
                app.autoTranslateChanged()
            })
            .disabled(language == nil)
            .animation(.snappy, value: autoTranslate)
            .help((hidden ? "Afficher la traduction" : shown ? "Masquer la traduction" : "Traduire ce son")
                  + (autoTranslate ? " · clic droit : traduction auto ∞ désactivée" : " · clic droit : traduire automatiquement ∞"))
            .animation(.snappy, value: hidden)
            .animation(.snappy, value: shown)
            .opacity(language == nil ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: language == nil)
        }
    }
}

/// Disque dur : ouvre / ferme la bibliothèque des sons déjà traduits.
private struct LibraryPill: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let active = app.libraryOpen
        Button { app.libraryOpen.toggle() } label: {
            Pill {
                Image(systemName: active ? "internaldrive.fill" : "internaldrive")
                    .foregroundStyle(active ? Color.black : Color.primary)
            }
            .background(Capsule().fill(active ? Color.white : .clear))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(active ? "Revenir aux paroles en cours" : "Sons déjà traduits")
        .animation(.snappy, value: active)
    }
}

/// Mode éco, fenêtre flottante (si activée dans les Réglages), Réglages et Quitter, dans une pilule.
struct AppButtons: View {
    @Environment(AppState.self) private var app
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.floatingWindowEnabled) private var floatingWindowEnabled = false

    var body: some View {
        Pill {
            HStack(spacing: 12) {
                // Plus de bouton éco : le lecteur réduit le remplace. Seul le mode éco (veille automatique
                // ou au lancement) garde la note verte pour revenir à la musique.
                if app.ecoMode {
                    Button {
                        changeBubbleLayout { app.setEcoMode(false) }
                    } label: {
                        Image(systemName: "music.note").foregroundStyle(Color.green)
                    }
                    .help("Quitter le mode éco")
                    Divider().frame(height: 14)
                }
                if !app.ecoMode {
                    // Replier la bulle (juste les commandes) ou la déplier (paroles).
                    Button { changeBubbleLayout { app.toggleBubbleCompact() } } label: {
                        Image(systemName: app.bubbleCompact ? "chevron.down" : "chevron.up")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .help(app.bubbleCompact ? "Afficher les paroles" : "Replier : juste les commandes")
                    Divider().frame(height: 14)
                }
                if floatingWindowEnabled && !app.ecoMode {
                    Button {
                        openWindow(id: FloatingWindowView.id)
                        NSApp.activate()
                        dismiss()        // referme la bulle, la fenêtre flottante prend le relais
                    } label: { Image(systemName: "macwindow.on.rectangle") }
                    .help("Fenêtre flottante")
                    Divider().frame(height: 14)
                }
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

struct ArtworkView: View {
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

/// Cœur à côté de l'étoile : garde la traduction de ce son pour toujours (pilule disque, jamais supprimée).
private struct LyricsFavoriteButton: View {
    @Environment(AppState.self) private var app
    @State private var taps = 0

    private var available: Bool {
        if case .loaded(let lyrics) = app.lyricsStatus { return !lyrics.isInstrumental }
        return false
    }

    var body: some View {
        let on = app.currentLyricsFavorited
        Button {
            taps += 1
            withAnimation(.snappy) { app.toggleCurrentLyricsFavorite() }
        } label: {
            Image(systemName: on ? "heart.fill" : "heart")
                .font(.title3.weight(.semibold))
                .foregroundStyle(on ? LyricsPalette.original : Color.white)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: taps)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(available ? 1 : 0.3)
        .disabled(!available)
        .id(app.track?.id)
        .help(on ? "Retirer des paroles favorites" : "Sauver cette traduction (jamais supprimée)")
    }
}

/// Étoile blanche vide ; jaune quand le morceau est dans les favoris de Musique.
/// Elle ne s'anime qu'au clic, pas quand on passe à un morceau déjà en favori.
struct FavoriteButton: View {
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

/// Capte uniquement le clic droit ; les clics gauches traversent jusqu'au bouton en dessous.
private struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    final class CatcherView: NSView {
        var action: () -> Void = {}
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .rightMouseDown ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with event: NSEvent) { action() }
    }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }
}
