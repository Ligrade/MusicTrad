import SwiftUI
import Translation

/// Paroles avec traduction, ligne en cours mise en avant et défilement automatique.
struct LyricsView: View {
    @Environment(AppState.self) private var app
    @AppStorage(SettingsKey.fontSize) private var fontSize = SettingsDefault.fontSize
    @AppStorage(SettingsKey.showOriginal) private var showOriginal = true
    @AppStorage(SettingsKey.translationScale) private var translationScale = SettingsDefault.translationScale
    @AppStorage(SettingsKey.blurInactive) private var blurInactive = true

    var body: some View {
        Group {
            if app.libraryOpen {
                LibraryView().transition(.opacity)
            } else {
                content.transition(.opacity)
            }
        }
            .animation(.easeInOut(duration: 0.25), value: app.libraryOpen)
            .animation(.easeInOut(duration: 0.25), value: app.track?.id)
            .animation(.easeInOut(duration: 0.35), value: app.lyricsStatus)
    }

    @ViewBuilder
    private var content: some View {
        switch app.playback {
        case .musicNotRunning:
            ContentUnavailableView {
                VStack(spacing: 10) {
                    // Logo de MusicTrad.
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    Text("Musique n'est pas ouverte")
                }
            } actions: {
                // Double croche : l'identité de l'app plutôt qu'un simple « play ».
                StartButton(title: "Ouvrir Musique", glyph: "♫") { app.openMusic() }
                    .padding(.top, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .stopped:
            ContentUnavailableView {
                Label("Aucune musique en lecture", systemImage: "pause.circle")
            } description: {
                if app.myStationLink == nil {
                    Text("Colle le lien de ta station dans Réglages › Général pour la lancer d'ici.")
                }
            } actions: {
                VStack(spacing: 10) {
                    if app.myStationLink != nil {
                        StartButton(title: "Ma station", symbol: "dot.radiowaves.left.and.right") { app.openMyStation() }
                    } else {
                        SettingsLink {
                            Label("Ajouter Ma station", systemImage: "plus.circle")
                        }
                    }
                    StartButton(title: "Mes likes", symbol: "heart.fill") { app.playFavorites() }
                }
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notAuthorized:
            message("lock", "Accès à Musique refusé",
                    "Autorise MusicTrad dans Réglages Système › Confidentialité et sécurité › Automatisation.")
        case .error(let msg):
            message("exclamationmark.triangle", "Erreur", msg)
        case .playing, .paused:
            lyricsContent
        }
    }

    @ViewBuilder
    private var lyricsContent: some View {
        switch app.lyricsStatus {
        case .idle, .loading:
            VStack { ProgressView(); Text("Recherche des paroles…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notFound:
            message("text.badge.xmark", "Aucune parole trouvée", "LRCLIB n'a pas de paroles pour ce morceau.")
        case .failed(let msg):
            message("wifi.exclamationmark", "Paroles indisponibles", msg)
        case .loaded(let lyrics) where lyrics.isInstrumental:
            message("pianokeys", "Morceau instrumental", "Pas de paroles à afficher.")
        case .loaded(let lyrics):
            VStack(spacing: 0) {
                TranslationBanner()
                lines(lyrics)
            }
            .id(app.track?.id)
            .transition(.opacity)
        }
    }

    private func lines(_ lyrics: Lyrics) -> some View {
        let current = app.currentLineIndex
        let translations = app.translations
        let onlyTranslation = !showOriginal && translations != nil

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: fontSize * 0.7) {
                    ForEach(lyrics.lines) { line in
                        LineRow(
                            original: line.text,
                            translation: translations?[safe: line.id],
                            isCurrent: line.id == current,
                            isPast: lyrics.isSynced && current.map { line.id < $0 } == true,
                            dimmed: lyrics.isSynced && current != nil,
                            onlyTranslation: onlyTranslation,
                            fontSize: fontSize,
                            translationScale: translationScale,
                            blurInactive: blurInactive,
                            sourceIsFrench: app.sourceLanguage?.isFrench == true,
                            onTap: line.time == nil ? nil : { app.seek(to: line) }
                        )
                        .id(line.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: current) { _, new in
                guard let new else { return }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) {
                    proxy.scrollTo(new, anchor: UnitPoint(x: 0, y: 0.4))
                }
            }
            .onAppear {
                if let current { proxy.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.4)) }
            }
        }
    }

    private func message(_ icon: String, _ title: String, _ detail: String) -> some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(detail))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Gros bouton rouge façon Musique (« Ouvrir Musique », « Ma station »).
private struct StartButton: View {
    let title: String
    var symbol: String? = nil
    /// Caractère affiché à la place d'un symbole (ex. « ♫ »).
    var glyph: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let glyph { Text(glyph) } else if let symbol { Image(systemName: symbol) }
            }
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Capsule().fill(LyricsPalette.original.opacity(hovering ? 1 : 0.88)))
                .scaleEffect(hovering ? 1.04 : 1)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
    }
}

enum LyricsPalette {
    /// Rouge de l'icône.
    static let original = Color(red: 1.0, green: 0.27, blue: 0.36)
    static let translation = Color.white
    static let background = Color.black
}

/// Une ligne de paroles. La graisse ne change jamais : la mise en avant passe par
/// l'opacité, l'échelle et le flou, qui ne modifient pas la mise en page (pas de saut de ligne).
struct LineRow: View {
    let original: String
    let translation: String?
    let isCurrent: Bool
    let isPast: Bool
    let dimmed: Bool
    let onlyTranslation: Bool
    let fontSize: Double
    let translationScale: Double
    let blurInactive: Bool
    /// Chanson en français : le français reste blanc et la traduction anglaise passe en rouge.
    var sourceIsFrench = false
    /// Paroles synchronisées : un clic replace Musique au début de la ligne.
    var onTap: (() -> Void)?
    @State private var hovering = false

    private var hasTranslation: Bool {
        guard let translation else { return false }
        return !translation.isEmpty && translation != original
    }

    var body: some View {
        Group {
            if original.trimmingCharacters(in: .whitespaces).isEmpty {
                BreakRow(isCurrent: isCurrent, fontSize: fontSize)
            } else {
                VStack(alignment: .leading, spacing: fontSize * 0.15) {
                    // Règle de couleur : le français en blanc, l'autre langue en rouge.
                    let originalColor = sourceIsFrench ? LyricsPalette.translation : LyricsPalette.original
                    let translationColor = sourceIsFrench ? LyricsPalette.original : LyricsPalette.translation
                    if onlyTranslation, hasTranslation, let translation {
                        Text(translation)
                            .font(.system(size: fontSize, weight: .bold))
                            .foregroundStyle(translationColor)
                    } else {
                        Text(original)
                            .font(.system(size: fontSize, weight: .bold))
                            .foregroundStyle(originalColor)
                        if hasTranslation, let translation {
                            Text(translation)
                                .font(.system(size: fontSize * translationScale, weight: .semibold))
                                .foregroundStyle(translationColor)
                                .transition(.opacity.combined(with: .offset(y: 6)))
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(dimmed && !isCurrent ? (isPast ? 0.28 : 0.42) : 1)
        .blur(radius: blurInactive && dimmed && !isCurrent ? 0.8 : 0)
        .scaleEffect(dimmed && !isCurrent ? 0.97 : 1, anchor: .leading)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: isCurrent)
        .animation(.easeOut(duration: 0.4), value: hasTranslation)
        .brightness(hovering && !isCurrent ? 0.12 : 0)
        .contentShape(.rect)
        .onTapGesture { onTap?() }
        .onHover { hovering = onTap != nil && $0 }
        .pointerStyle(onTap == nil ? nil : .link)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Passage instrumental : ♪♪♪ qui s'allument l'un après l'autre au fil du solo
/// (comme les points de Musique), respirent doucement, puis grossissent et s'effacent
/// juste avant la reprise du chant.
private struct BreakRow: View {
    @Environment(AppState.self) private var app
    let isCurrent: Bool
    let fontSize: Double
    @State private var breathing = false

    var body: some View {
        let progress = isCurrent ? app.breakProgress : 0
        // Dernier dixième : les notes grossissent puis disparaissent.
        let ending = min(max((progress - 0.9) / 0.1, 0), 1)
        HStack(spacing: fontSize * 0.25) {
            ForEach(0..<3, id: \.self) { i in
                let fill = isCurrent ? min(max(progress * 3 - Double(i), 0), 1) : 0
                Text("♪")
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(LyricsPalette.translation)
                    .opacity(isCurrent ? 0.25 + 0.75 * fill : 0.7)
                    .scaleEffect(1 + 0.12 * fill, anchor: .bottom)
            }
        }
        // Respiration seulement sur le passage en cours (une animation infinie par ligne coûterait du CPU).
        .scaleEffect(breathing ? 1.06 : 1, anchor: .leading)
        .animation(breathing ? .easeInOut(duration: 1.4).repeatForever() : .easeOut(duration: 0.3), value: breathing)
        .onAppear { breathing = isCurrent }
        .onChange(of: isCurrent) { _, now in breathing = now }
        .scaleEffect(1 + 0.3 * ending, anchor: .leading)
        .opacity(1 - ending)
        .animation(.easeOut(duration: 0.25), value: progress)
    }
}

/// État de la traduction au-dessus des paroles.
private struct TranslationBanner: View {
    @Environment(AppState.self) private var app
    @State private var downloadConfig: TranslationSession.Configuration?

    var body: some View {
        Group {
            if app.calibrating {
                HStack(spacing: 10) {
                    Label("Clique sur la ligne chantée en ce moment", systemImage: "scope")
                        .foregroundStyle(LyricsPalette.original)
                    Button("Annuler") { app.cancelCalibration() }.controlSize(.small)
                }
            } else {
            switch app.translationStatus {
            case .needsDownload(let lang, let target):
                HStack {
                    Text("Langue « \(lang.displayName) » à télécharger.")
                    Button("Télécharger") {
                        downloadConfig = .init(source: lang, target: target)
                    }
                }
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            case .idle, .done, .alreadyFrench, .translating, .partial:   // l'avancement est sur la pilule de langue
                EmptyView()
            }
            }
        }
        .font(.body)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .translationTask(downloadConfig) { session in
            // La session n'est utilisée qu'ici : pas de partage réel entre threads.
            nonisolated(unsafe) let session = session
            try? await session.prepareTranslation()
            downloadConfig = nil
            app.retranslate()
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
