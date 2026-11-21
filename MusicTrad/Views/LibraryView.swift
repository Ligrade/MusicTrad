import SwiftUI

/// Bibliothèque des sons déjà traduits : la liste, puis les paroles du son choisi.
struct LibraryView: View {
    @Environment(AppState.self) private var app
    @State private var entries: [LibraryEntry]?
    @State private var query = ""
    @State private var selected: LibraryEntry?
    @State private var usedBytes: Int64?

    var body: some View {
        ZStack {
            if let selected {
                LibraryDetail(entry: selected) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { self.selected = nil }
                } onDelete: {
                    Task {
                        await app.deleteLibraryTranslation(selected)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                            entries?.removeAll { $0.id == selected.id }
                            self.selected = nil
                        }
                        usedBytes = await CacheManager.shared.stats().bytes
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                list
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .clipped()
        .task {
            // Lecture du cache hors du fil principal (quelques centaines de petits fichiers).
            let loaded = await Task.detached(priority: .userInitiated) { TranslatedLibrary.load() }.value
            withAnimation(.easeOut(duration: 0.2)) { entries = loaded }
            app.refreshLibraryProtection(loaded)
            usedBytes = await CacheManager.shared.stats().bytes
        }
    }

    private var filtered: [LibraryEntry] {
        // Favoris en tête, puis les plus récemment écoutés.
        let all = (entries ?? []).sorted { a, b in
            let fa = app.libraryFavorites.contains(a.id), fb = app.libraryFavorites.contains(b.id)
            return fa != fb ? fa : a.lastUsed > b.lastUsed
        }
        let q = query.trimmingCharacters(in: .whitespaces).normalizedForMatch
        guard !q.isEmpty else { return all }
        return all.filter { "\($0.title) \($0.artist)".normalizedForMatch.contains(q) }
    }

    @ViewBuilder
    private var list: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sons traduits").font(.title2.bold())
                    Spacer()
                    if let entries {
                        Text("\(entries.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Titre ou artiste", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(.quaternary, in: .capsule)
                StorageInfo(usedBytes: usedBytes)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 10)

            if entries == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "Aucun son traduit" : "Aucun résultat",
                    systemImage: query.isEmpty ? "internaldrive" : "magnifyingglass",
                    description: Text(query.isEmpty ? "Les sons que tu écoutes apparaîtront ici une fois traduits." : "")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { entry in
                            LibraryRow(entry: entry, isPlaying: isPlaying(entry),
                                       isFavorite: app.libraryFavorites.contains(entry.id)) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { selected = entry }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private func isPlaying(_ entry: LibraryEntry) -> Bool {
        guard let t = app.track else { return false }
        return "\(t.artist) – \(t.title)" == entry.id
    }
}

private struct LibraryRow: View {
    let entry: LibraryEntry
    let isPlaying: Bool
    let isFavorite: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LibraryArtwork(entry: entry, size: 40)
                    .overlay {
                        if isPlaying {
                            // Son en cours d'écoute.
                            RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.5))
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(LyricsPalette.original)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(.headline).lineLimit(1)
                    Text(entry.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(LyricsPalette.original)
                }
                Text(entry.pair)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.08 : 0)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Paroles et traduction d'un son de la bibliothèque, à relire tranquillement.
private struct LibraryDetail: View {
    let entry: LibraryEntry
    let back: () -> Void
    let onDelete: () -> Void
    @State private var confirmDelete = false
    @State private var hoveringTrash = false
    @AppStorage(SettingsKey.fontSize) private var fontSize = SettingsDefault.fontSize
    @AppStorage(SettingsKey.showOriginal) private var showOriginal = true
    @AppStorage(SettingsKey.translationScale) private var translationScale = SettingsDefault.translationScale

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: back) {
                    Label("Sons traduits", systemImage: "chevron.left")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            HStack(spacing: 14) {
                LibraryArtwork(entry: entry, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        Text(entry.title).font(.title2.bold()).lineLimit(2)
                        PlayNowButton(entry: entry)
                        FavoriteLyricsButton(entry: entry)
                    }
                    Text(entry.artist).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                // Langues, et en dessous la corbeille pour supprimer cette traduction.
                VStack(alignment: .trailing, spacing: 8) {
                    Text(entry.pair).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Button { confirmDelete = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(hoveringTrash ? LyricsPalette.original : Color.secondary)
                            .frame(width: 26, height: 22, alignment: .trailing)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveringTrash = $0 }
                    .help("Supprimer cette traduction")
                    .confirmationDialog("Supprimer la traduction de « \(entry.title) » ?", isPresented: $confirmDelete) {
                        Button("Supprimer", role: .destructive, action: onDelete)
                    } message: {
                        Text("Elle disparaît de la liste et sera refaite à la prochaine écoute.")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: fontSize * 0.7) {
                    ForEach(entry.lyrics.lines) { line in
                        // Pas de « ♪ » animés ici : une pause = un simple espace.
                        if line.isBlank {
                            Color.clear.frame(height: fontSize * 0.4)
                        } else {
                            LineRow(
                                original: line.text,
                                translation: entry.translation[safe: line.id],
                                isCurrent: false,
                                isPast: false,
                                dimmed: false,
                                onlyTranslation: !showOriginal,
                                fontSize: fontSize,
                                translationScale: translationScale,
                                blurInactive: false,
                                sourceIsFrench: entry.sourceIsFrench
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Pochette d'un son de la bibliothèque, chargée à la demande (iTunes Search, puis cache disque).
private struct LibraryArtwork: View {
    @Environment(AppState.self) private var app
    let entry: LibraryEntry
    let size: CGFloat
    @State private var image: NSImage?

    /// Pochettes déjà affichées : la page d'un son s'ouvre avec sa pochette, sans clignoter.
    @MainActor static var memory: [String: NSImage] = [:]

    init(entry: LibraryEntry, size: CGFloat) {
        self.entry = entry
        self.size = size
        _image = State(initialValue: Self.memory[entry.id])
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18).fill(Color.white.opacity(0.08))
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(LyricsPalette.original)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.18))
        .task(id: entry.id) {
            guard image == nil else { return }
            let loaded = await app.libraryArtwork(entry)
            if let loaded { Self.memory[entry.id] = loaded }
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

/// Petit bouton rouge ▶︎ à côté du titre : écouter le son maintenant.
private struct PlayNowButton: View {
    @Environment(AppState.self) private var app
    let entry: LibraryEntry
    @State private var hovering = false

    var body: some View {
        Button { app.playFromLibrary(entry) } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(LyricsPalette.original.opacity(hovering ? 1 : 0.88)))
                .scaleEffect(hovering ? 1.08 : 1)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .help("Écouter maintenant")
    }
}

/// Place restante dans le cache (limite choisie dans les Réglages) et règle de suppression.
private struct StorageInfo: View {
    let usedBytes: Int64?
    // Suivent en direct ce qui est choisi dans Réglages › Cache.
    @AppStorage(SettingsKey.cacheLimitMB) private var limitMB = CacheManager.defaultLimitMB
    @AppStorage(SettingsKey.cacheMaxAgeDays) private var days = CacheManager.defaultMaxAgeDays

    var body: some View {
        let limit = Int64(limitMB > 0 ? limitMB : CacheManager.defaultLimitMB) * 1_000_000
        let age = CacheManager.maxAgeChoices.first { $0.days == days }?.label ?? "\(days) jours"
        VStack(alignment: .leading, spacing: 6) {
            if let usedBytes {
                ProgressView(value: Double(min(usedBytes, limit)), total: Double(limit))
                    .tint(LyricsPalette.original)
                HStack {
                    SettingsCacheLink("\(Self.format(max(limit - usedBytes, 0))) libres sur \(Self.format(limit))")
                    Spacer()
                    SettingsCacheLink(days == 0 ? "Jamais supprimé pour l'âge" : "Supprimé après \(age) sans écoute")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Label("Les paroles favorites ne sont jamais supprimées.", systemImage: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Cœur à côté du titre : garde ces paroles pour toujours (jamais purgées).
private struct FavoriteLyricsButton: View {
    @Environment(AppState.self) private var app
    let entry: LibraryEntry
    @State private var taps = 0

    var body: some View {
        let on = app.libraryFavorites.contains(entry.id)
        Button {
            taps += 1
            withAnimation(.snappy) { app.toggleLibraryFavorite(entry) }
        } label: {
            Image(systemName: on ? "heart.fill" : "heart")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(on ? LyricsPalette.original : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: taps)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(on ? "Retirer des favoris" : "Paroles favorites : jamais supprimées")
    }
}

/// Texte souligné au survol ; un clic ouvre Réglages › Cache (et referme la bulle).
private struct SettingsCacheLink: View {
    let text: String
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inMenuBubble) private var inMenuBubble
    @State private var hovering = false

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .underline(hovering)
            .foregroundStyle(hovering ? Color.primary : Color.secondary)
            .onHover { hovering = $0 }
            .onTapGesture {
                UserDefaults.standard.set("cache", forKey: SettingsKey.settingsTab)
                if inMenuBubble { dismiss() }
                openSettings()
                NSApp.activate()
            }
            .pointerStyle(.link)
            .help("Modifier dans Réglages › Cache")
    }
}
