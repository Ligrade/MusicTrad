import ServiceManagement
import SwiftUI

/// Réglages en onglets : Général, Affichage, Traduction, Cache.
struct SettingsView: View {
    /// Version lue dans l'Info.plist (CFBundleShortVersionString).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Onglet affiché (un lien de la bulle peut ouvrir directement « Cache »).
    @AppStorage(SettingsKey.settingsTab) private var tab = "general"

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                Tab("Général", systemImage: "gearshape", value: "general") { GeneralSettings() }
                Tab("Affichage", systemImage: "textformat.size", value: "display") { DisplaySettings() }
                Tab("Traduction", systemImage: "character.bubble", value: "translation") { TranslationSettings() }
                Tab("Cache", systemImage: "internaldrive", value: "cache") { CacheSettings() }
            }
            Text("MusicTrad · Version \(Self.version) by Ligrade")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
        }
        .frame(width: 580)
    }
}

// MARK: - Général

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.floatingWindowEnabled) private var floatingWindowEnabled = false
    @AppStorage(SettingsKey.openWindowAtLaunch) private var openWindowAtLaunch = false
    @AppStorage(SettingsKey.ecoAtLaunch) private var ecoAtLaunch = false
    @AppStorage(SettingsKey.onboardingSeen) private var onboardingSeen = false
    @AppStorage(SettingsKey.autoEcoMinutes) private var autoEcoMinutes = 30
    @AppStorage(SettingsKey.myStationURL) private var myStationURL = ""
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Ouvrir MusicTrad à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
                Button("Revoir la présentation des fonctions") { onboardingSeen = false }
                    .disabled(!onboardingSeen)
                Toggle("Démarrer en mode éco", isOn: $ecoAtLaunch)
                Text("L'app se lance en veille : clique sur le bouton vert pour la réactiver.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Mode éco automatique", selection: $autoEcoMinutes) {
                    Text("Après 30 min").tag(30)
                    Text("Après 1 h").tag(60)
                    Text("Après 2 h").tag(120)
                    Text("Après 4 h").tag(240)
                    Text("Jamais").tag(0)
                }
                Text("Si tu n'ouvres pas la bulle ni la fenêtre pendant ce temps, l'app se met en veille toute seule.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextField("Lien", text: $myStationURL, prompt: Text("https://music.apple.com/…/station/…"))
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Ma station")
            } footer: {
                Text("Quand rien ne joue, le bouton « Ma station » ouvre ta station dans Musique. Pour le lien : dans Musique, clic droit (ou ⋯) sur « Station de : … » › Partager › Copier le lien, puis colle-le ici.")
            }

            Section {
                Toggle("Activer la fenêtre flottante", isOn: $floatingWindowEnabled)
                    .toggleStyle(.checkbox)
                    .onChange(of: floatingWindowEnabled) { _, on in
                        if !on { dismissWindow(id: FloatingWindowView.id) }
                    }
                Toggle("L'afficher au lancement de l'app", isOn: $openWindowAtLaunch)
                    .toggleStyle(.checkbox)
                    .disabled(!floatingWindowEnabled)
                    .padding(.leading, 20)
            } header: {
                Text("Fenêtre flottante")
            } footer: {
                Text("Désactivée par défaut. Une fois cochée, son bouton apparaît dans la pilule en haut à droite de la bulle, juste après le mode éco. Elle reste toujours au premier plan.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Accès à Musique") {
                LabeledContent("Autorisation") {
                    Button("Ouvrir les réglages d'automatisation") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Affichage

private struct DisplaySettings: View {
    @AppStorage(SettingsKey.fontSize) private var fontSize = SettingsDefault.fontSize
    @AppStorage(SettingsKey.translationScale) private var translationScale = SettingsDefault.translationScale
    @AppStorage(SettingsKey.showOriginal) private var showOriginal = true
    @AppStorage(SettingsKey.blurInactive) private var blurInactive = true
    @AppStorage(SettingsKey.syncOffset) private var syncOffset = SettingsDefault.syncOffset
    @AppStorage(SettingsKey.animatedArtwork) private var animatedArtwork = false
    @AppStorage(SettingsKey.albumBackground) private var albumBackground = true

    var body: some View {
        Form {
            Section {
                Picker("Fond des paroles", selection: $albumBackground) {
                    Text("Noir").tag(false)
                    Text("Couleur de l'album").tag(true)
                }
                Toggle("Pochette animée", isOn: $animatedArtwork)
            } header: {
                Text("Apparence")
            } footer: {
                Text("Couleur de l'album : la pochette floutée derrière les paroles, en fondu d'un son à l'autre. Pochette animée : quand l'album en a une sur Apple Music, elle remplit le lecteur réduit pendant la lecture, et se met en pause dès qu'une autre fenêtre passe devant. Consomme un peu plus.")
            }

            Section("Texte") {
                LabeledContent("Taille des paroles") {
                    HStack {
                        Slider(value: $fontSize, in: 14...44, step: 1)
                        Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                LabeledContent("Taille de la traduction") {
                    HStack {
                        Slider(value: $translationScale, in: 0.6...1.0, step: 0.05)
                        Text("\(Int(translationScale * 100)) %").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                Toggle("Afficher les paroles originales", isOn: $showOriginal)
                Toggle("Flouter les lignes qui ne sont pas chantées", isOn: $blurInactive)
            }

            Section("Aperçu") {
                VStack(alignment: .leading, spacing: fontSize * 0.15) {
                    if showOriginal {
                        Text("All over the world")
                            .font(.system(size: fontSize, weight: .bold))
                            .foregroundStyle(LyricsPalette.original)
                    }
                    Text("Partout dans le monde")
                        .font(.system(size: showOriginal ? fontSize * translationScale : fontSize,
                                      weight: showOriginal ? .semibold : .bold))
                        .foregroundStyle(LyricsPalette.translation)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(LyricsPalette.background, in: .rect(cornerRadius: 10))
            }

            Section {
                LabeledContent("Décalage de synchronisation") {
                    HStack {
                        Slider(value: $syncOffset, in: -1.5...1.5, step: 0.1)
                        Text(String(format: "%+.1f s", syncOffset)).monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                Button("Rétablir") { syncOffset = SettingsDefault.syncOffset }
            } header: {
                Text("Synchronisation")
            } footer: {
                Text("Valeur positive : la ligne s'allume plus tôt. Utile si les paroles sont en retard sur la voix.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Traduction

private struct TranslationSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage(SettingsKey.engine) private var engine = TranslationEngine.apple
    @AppStorage(SettingsKey.prefetchNext) private var prefetchNext = true
    @AppStorage(SettingsKey.frenchToEnglish) private var frenchToEnglish = false
    @AppStorage(SettingsKey.autoTranslate) private var autoTranslate = false

    @State private var apiKey = ""
    @State private var hasKey = KeychainStore.load() != nil
    @State private var keyMessage: String?
    @State private var usage: (used: Int, limit: Int)?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Picker("Moteur", selection: $engine) {
                    ForEach(TranslationEngine.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Toggle("Traduire automatiquement", isOn: $autoTranslate)
                    .onChange(of: autoTranslate) { app.autoTranslateChanged() }
                Text("Désactivé : rien n'est traduit tant que tu ne cliques pas sur la pilule « EN → FR ». Un son déjà traduit s'affiche directement. Raccourci : clic droit sur la pilule (∞ quand c'est activé).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Préparer le morceau suivant à l'avance", isOn: $prefetchNext)
                Text(autoTranslate ? "Paroles et traduction du son suivant prêtes avant qu'il commence."
                                   : "Paroles du son suivant prêtes à l'avance. Sa traduction aussi quand la traduction automatique (∞) est activée.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Traduire les chansons en français en anglais", isOn: $frenchToEnglish)
                    .onChange(of: frenchToEnglish) { app.frenchToEnglishChanged() }
            } header: {
                Text("Traduction")
            } footer: {
                Text(engine == .apple
                     ? "Traduction sur le Mac, sans compte. Si une langue manque, un bouton « Télécharger » apparaît au-dessus des paroles."
                     : "Chaque morceau n'est traduit qu'une fois, puis gardé en cache.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if engine == .deepl {
                Section("Clé DeepL") {
                    HStack {
                        SecureField(hasKey ? "Clé enregistrée dans le Trousseau" : "Colle ta clé (…:fx)", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Enregistrer") { saveKey() }
                            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if hasKey {
                        HStack {
                            Button(testing ? "Vérification…" : "Tester la clé") { Task { await testKey() } }
                                .disabled(testing)
                            Spacer()
                            Button("Supprimer la clé", role: .destructive) {
                                KeychainStore.delete()
                                hasKey = false
                                usage = nil
                                keyMessage = "Clé supprimée."
                            }
                        }
                    }
                    if let usage, usage.limit > 0 {
                        LabeledContent("Utilisé ce mois-ci") {
                            Text("\(usage.used.formatted()) / \(usage.limit.formatted()) caractères")
                                .monospacedDigit()
                        }
                        ProgressView(value: Double(usage.used), total: Double(usage.limit))
                    }
                    if let keyMessage { Text(keyMessage).font(.caption).foregroundStyle(.secondary) }
                    Link("Obtenir une clé DeepL gratuite (500 000 caractères par mois)",
                         destination: URL(string: "https://www.deepl.com/pro-api")!)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: engine) { app.retranslate() }
        .task(id: engine) { if engine == .deepl, hasKey { await testKey() } }
    }

    private func saveKey() {
        let ok = KeychainStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        hasKey = ok
        keyMessage = ok ? "Clé enregistrée." : "Échec de l'enregistrement."
        apiKey = ""
        if ok {
            app.retranslate()
            Task { await testKey() }
        }
    }

    private func testKey() async {
        guard let key = KeychainStore.load() else { return }
        testing = true
        defer { testing = false }
        do {
            usage = try await DeepLTranslator.usage(key: key)
            keyMessage = "Clé valide."
        } catch {
            usage = nil
            keyMessage = error.localizedDescription
        }
    }
}

// MARK: - Cache

private struct CacheSettings: View {
    @AppStorage(SettingsKey.cacheLimitMB) private var cacheLimitMB = CacheManager.defaultLimitMB
    @AppStorage(SettingsKey.cacheMaxAgeDays) private var cacheMaxAgeDays = CacheManager.defaultMaxAgeDays
    @State private var stats: CacheManager.Stats?
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Utilisation") {
                LabeledContent("Espace utilisé") {
                    if let stats {
                        Text("\(ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .file)) sur \(cacheLimitMB) Mo")
                            .monospacedDigit()
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                if let stats {
                    ProgressView(value: min(Double(stats.bytes), Double(cacheLimitMB) * 1_000_000),
                                 total: Double(cacheLimitMB) * 1_000_000)
                    LabeledContent("Titres en cache", value: stats.songs.formatted())
                    LabeledContent("Favoris protégés", value: stats.protectedSongs.formatted())
                    if let oldest = stats.oldestUse {
                        LabeledContent("Plus ancienne écoute", value: oldest.formatted(date: .long, time: .omitted))
                    }
                }
            }

            Section {
                Picker("Taille maximale", selection: $cacheLimitMB) {
                    ForEach(CacheManager.limitChoices, id: \.self) { mb in
                        Text("\(mb) Mo (≈ \((mb * 1000 / 8).formatted()) titres)").tag(mb)
                    }
                }
                Picker("Supprimer si pas écouté depuis", selection: $cacheMaxAgeDays) {
                    ForEach(CacheManager.maxAgeChoices, id: \.days) { Text($0.label).tag($0.days) }
                }
            } header: {
                Text("Limites")
            } footer: {
                Text("Nettoyage au lancement puis chaque jour : d'abord les titres trop anciens, puis les moins récemment écoutés si la taille maximale est dépassée. Les titres favoris sont toujours gardés.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Afficher dans le Finder") {
                        try? FileManager.default.createDirectory(at: CacheManager.shared.folderURL, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([CacheManager.shared.folderURL])
                    }
                    Button("Nettoyer maintenant") { Task { await prune() } }
                    Spacer()
                    Button("Vider le cache…", role: .destructive) { confirmClear = true }
                }
            }
        }
        .formStyle(.grouped)
        .task { stats = await CacheManager.shared.stats() }
        .onChange(of: cacheLimitMB) { Task { await prune() } }
        .onChange(of: cacheMaxAgeDays) { Task { await prune() } }
        .confirmationDialog("Vider le cache ?", isPresented: $confirmClear) {
            Button("Vider", role: .destructive) {
                Task {
                    await CacheManager.shared.clearAll()
                    stats = await CacheManager.shared.stats()
                }
            }
        } message: {
            Text("Paroles, traductions et pochettes seront supprimées, sauf les titres likés et les paroles favorites. Le reste sera récupéré à nouveau à la prochaine écoute.")
        }
    }

    private func prune() async {
        stats = await CacheManager.shared.prune(limitMB: cacheLimitMB, maxAgeDays: cacheMaxAgeDays)
    }
}
