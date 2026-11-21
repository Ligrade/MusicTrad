import SwiftUI

/// Bibliothèque des sons déjà traduits : la liste, puis les paroles du son choisi.
struct LibraryView: View {
    @Environment(AppState.self) private var app
    @State private var entries: [LibraryEntry]?
    @State private var query = ""
    @State private var selected: LibraryEntry?

    var body: some View {
        ZStack {
            if let selected {
                LibraryDetail(entry: selected) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { self.selected = nil }
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
        }
    }

    private var filtered: [LibraryEntry] {
        let all = entries ?? []
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
                            LibraryRow(entry: entry, isPlaying: isPlaying(entry)) {
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
                .foregroundStyle(LyricsPalette.original)
                Spacer()
                Text(entry.pair).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            HStack(spacing: 14) {
                LibraryArtwork(entry: entry, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        Text(entry.title).font(.title2.bold()).lineLimit(2)
                        PlayNowButton(entry: entry)
                    }
                    Text(entry.artist).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
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
            let loaded = await app.libraryArtwork(entry)
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
