import AppKit
import Foundation
import Observation
import OSLog

/// Coordonne lecteur → paroles → traduction.
/// Le travail lui-même est ailleurs : horloge de lecture (PlaybackClock), paroles (LyricsStore),
/// traductions (TranslationStore). AppState garde l'état affiché et décide quoi charger et quand.
@Observable
final class AppState {
    private(set) var playback: PlaybackState = .musicNotRunning
    private(set) var lyricsStatus: LyricsStatus = .idle
    private(set) var translationStatus: TranslationStatus = .idle
    private(set) var sourceLanguage: Locale.Language?
    private(set) var artwork: NSImage? {
        didSet { artworkBackdrop = artwork.flatMap(ArtworkBackdrop.make(from:)) }
    }
    /// Pochette réduite et floutée pour les fonds « couleur de l'album » (voir ArtworkBackdrop).
    private(set) var artworkBackdrop: NSImage?
    /// Morceau auquel appartient la pochette affichée : la pochette ne change (et ne s'anime)
    /// qu'une fois la nouvelle chargée, pour qu'elle prenne directement la place de l'ancienne.
    private(set) var artworkID: String?
    /// Sens de l'animation de la pochette : vrai après ⏮ (arrive par la gauche).
    private(set) var artworkFromLeading = false
    /// Valeur affichée tout de suite après un clic, en attendant que Musique la confirme.
    private var favoriteOverride: (id: String, value: Bool)?
    private(set) var favoriteError: String?

    private let monitor = MusicPlayerMonitor()
    private let lyricsStore = LyricsStore()
    private let translationStore = TranslationStore()
    private var currentTrackID: String?
    private var loadTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private let artworkService: ArtworkService
    @ObservationIgnored private let nextTrackPredictor: NextTrackPredictor
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var maintenanceTask: Task<Void, Never>?
    @ObservationIgnored private var protectionSignature: String?
    private static let log = Logger(subsystem: "fr.dynamicagence.MusicTrad", category: "prefetch")

    var track: TrackInfo? { playback.track }

    var lyrics: Lyrics? {
        if case .loaded(let l) = lyricsStatus { return l }
        return nil
    }

    var translations: [String]? {
        switch translationStatus {
        case .done(let t), .partial(let t): return t
        default: return nil
        }
    }

    /// Ligne chantée, recalculée 20 fois par seconde à partir d'une horloge locale
    /// (Musique n'est interrogée que toutes les 0,5 s). Légère avance réglable.
    private(set) var currentLineIndex: Int?
    /// Nombre de vues de paroles ouvertes (bulle, fenêtre flottante) : sans elles, l'app ralentit.
    @ObservationIgnored private var visibleViews = 0
    /// Dernière fois que la bulle ou la fenêtre était à l'écran (pour la mise en veille automatique).
    @ObservationIgnored private var lastUse = Date()
    /// Dernière fois que de la musique jouait (sans musique pendant le délai choisi : mode éco).
    @ObservationIgnored private var lastMusic = Date()
    /// Le prochain morceau vu sera traduit tout de suite (clic droit « Paroles + traduction » depuis le mode éco).
    @ObservationIgnored private var translateNextTrack = false
    /// En mode éco automatique : réveil (en lecteur) dès que Musique se remet à jouer.
    @ObservationIgnored private var ecoWakeObserver: NSObjectProtocol?

    /// Une bulle ou une fenêtre est à l'écran : les animations infinies (♪ qui respirent, pilule qui clignote)
    /// s'arrêtent sinon, car la fenêtre de la barre des menus reste vivante une fois fermée.
    private(set) var isOnScreen = false

    func viewAppeared() {
        visibleViews += 1
        isOnScreen = true
        lastUse = .now
        guard visibleViews == 1, !ecoMode else { return }
        // Première vue ouverte : relecture immédiate de Musique et horloge réveillée tout de suite.
        monitor.setVisible(true)
        startTicker()
    }

    func viewDisappeared() {
        visibleViews = max(0, visibleViews - 1)
        isOnScreen = visibleViews > 0
        lastUse = .now
        // Plus rien à l'écran : Musique n'est relue qu'à ses notifications (l'horloge ralentit seule).
        if visibleViews == 0 { monitor.setVisible(false) }
    }

    /// Position de lecture estimée entre deux lectures de Musique.
    @ObservationIgnored private var clock = PlaybackClock()
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Position estimée maintenant : dernière position lue + temps écoulé depuis.
    private var livePosition: TimeInterval { clock.position }

    /// Position estimée maintenant (pour la barre de progression du petit lecteur).
    var playerPosition: TimeInterval { livePosition }

    /// Avancement (0 → 1) du passage instrumental en cours, pour l'animation ♪♪♪.
    private(set) var breakProgress: Double = 0

    private func refreshCurrentLine() {
        let position = livePosition + Preferences.syncOffset + songOffset
        let index = lyrics?.lineIndex(at: position)
        if index != currentLineIndex { currentLineIndex = index }
        if let index, let lines = lyrics?.lines, lines[index].isBlank, let start = lines[index].time,
           index + 1 < lines.count, let end = lines[index + 1].time, end > start {
            let p = min(max((position - start) / (end - start), 0), 1)
            if abs(p - breakProgress) >= 0.01 { breakProgress = p }
        } else if breakProgress != 0 {
            breakProgress = 0
        }
    }

    // MARK: AirPlay

    private(set) var airPlayDevices: [AirPlayDevice] = []
    /// Vrai si le son part ailleurs que sur le Mac (icône AirPlay colorée).
    var airPlayActive: Bool { airPlayDevices.contains { $0.selected && !$0.isComputer } }

    func refreshAirPlay() {
        Task { airPlayDevices = await monitor.runner.airPlayDevices() }
    }

    /// Clic sur une sortie : elle seule. Avec `addToGroup`, on l'ajoute ou la retire du groupe.
    func selectAirPlay(_ device: AirPlayDevice, addToGroup: Bool = false) {
        Task {
            if addToGroup {
                // On garde toujours au moins une sortie.
                if device.selected, airPlayDevices.filter(\.selected).count <= 1 { return }
                await monitor.runner.selectAirPlay(device.name, exclusive: false, selected: !device.selected)
            } else {
                await monitor.runner.selectAirPlay(device.name, exclusive: true)
            }
            airPlayDevices = await monitor.runner.airPlayDevices()
        }
    }

    // MARK: Lancer Musique

    /// Musique fermée : bouton « Ouvrir Musique ».
    func openMusic() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Music.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    /// Lien de « Ma station » collé dans les Réglages (Musique ne permet pas de la lancer par script).
    var myStationLink: URL? {
        guard let raw = UserDefaults.standard.string(forKey: SettingsKey.myStationURL)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              raw.contains("music.apple.com"), raw.contains("/station/") else { return nil }
        return URL(string: raw.replacingOccurrences(of: "https://", with: "music://"))
    }

    /// Rien en lecture : ouvre « Ma station » grâce au lien enregistré dans les Réglages
    /// (Musique ne donne aucun autre moyen d'atteindre la station personnelle).
    func openMyStation() {
        guard let link = myStationLink else { return }
        NSWorkspace.shared.open(link)
    }

    /// Rien en lecture : lance les morceaux likés.
    func playFavorites() {
        Task { await monitor.runner.playFavorites() }
    }

    /// Paroles favorites de la bibliothèque (« Artiste – Titre ») : jamais supprimées par le nettoyage du cache.
    private(set) var libraryFavorites = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.libraryFavorites) ?? [])

    func toggleLibraryFavorite(_ entry: LibraryEntry) {
        let on = !libraryFavorites.contains(entry.id)
        if on { libraryFavorites.insert(entry.id) } else { libraryFavorites.remove(entry.id) }
        UserDefaults.standard.set(Array(libraryFavorites).sorted(), forKey: SettingsKey.libraryFavorites)
        CacheManager.shared.setProtected(on, song: "library|\(entry.id)", files: entry.files)
    }

    /// Son en cours dans les paroles favorites (cœur à côté de l'étoile) ?
    var currentLyricsFavorited: Bool {
        guard let track else { return false }
        return libraryFavorites.contains("\(track.artist) – \(track.title)")
    }

    /// Cœur : garde pour toujours les paroles, la traduction et la pochette du son en cours.
    func toggleCurrentLyricsFavorite() {
        guard let track, let lyrics, !lyrics.isInstrumental else { return }
        let id = "\(track.artist) – \(track.title)"
        let on = !libraryFavorites.contains(id)
        if on { libraryFavorites.insert(id) } else { libraryFavorites.remove(id) }
        UserDefaults.standard.set(Array(libraryFavorites).sorted(), forKey: SettingsKey.libraryFavorites)
        let keys = [LyricsStore.key(for: track), TranslationStore.key(track, lyrics, engine, translationTarget),
                    "\(track.artist)|\(track.album)", "library|\(track.artist)|\(track.title)"]
        CacheManager.shared.setProtected(on, song: "library|\(id)", files: keys.map(DiskCache.fileName(for:)))
    }

    /// Poubelle de la bibliothèque : supprime la traduction de ce son (et le retire des favoris).
    /// Elle sera refaite à la prochaine écoute.
    func deleteLibraryTranslation(_ entry: LibraryEntry) async {
        if libraryFavorites.remove(entry.id) != nil {
            UserDefaults.standard.set(Array(libraryFavorites).sorted(), forKey: SettingsKey.libraryFavorites)
            CacheManager.shared.setProtected(false, song: "library|\(entry.id)", files: [])
        }
        await CacheManager.shared.removeTranslations(entry.translationFiles)
    }

    /// Remet à jour la protection des favoris (les fichiers changent si un son est retraduit).
    func refreshLibraryProtection(_ entries: [LibraryEntry]) {
        for entry in entries where libraryFavorites.contains(entry.id) {
            CacheManager.shared.setProtected(true, song: "library|\(entry.id)", files: entry.files)
        }
    }

    /// Pochette d'un son de la bibliothèque des traductions.
    func libraryArtwork(_ entry: LibraryEntry) async -> NSImage? {
        await artworkService.libraryArtwork(artist: entry.artist, title: entry.title, album: entry.album).flatMap(NSImage.init(data:))
    }

    /// Bibliothèque : lance le son tout de suite et revient aux paroles en direct.
    /// S'il n'est pas dans la bibliothèque Musique, ouvre sa page Apple Music.
    func playFromLibrary(_ entry: LibraryEntry) {
        libraryOpen = false   // retour immédiat aux paroles en direct
        Task {
            if await monitor.runner.play(title: entry.title, artist: entry.artist) {
                return
            } else if let url = await artworkService.songURL(artist: entry.artist, title: entry.title) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Clic sur l'artiste : ouvre sa page dans Musique.
    func openArtist() {
        guard let track else { return }
        Task {
            if let url = await artworkService.artistURL(for: track), NSWorkspace.shared.open(url) { return }
            await monitor.runner.revealCurrentTrack()
        }
    }

    /// Clic sur la pochette : ouvre l'album dans Musique.
    func openAlbum() {
        guard let track else { return }
        Task {
            if let url = await artworkService.albumURL(for: track), NSWorkspace.shared.open(url) { return }
            await monitor.runner.revealCurrentTrack()
        }
    }

    /// Pochette animée de l'album en cours (Apple Music), si l'option est activée et que l'album en a une.
    func motionArtwork() async -> URL? {
        guard let track, UserDefaults.standard.bool(forKey: SettingsKey.animatedArtwork) else { return nil }
        return await artworkService.motionArtwork(for: track)
    }

    /// Barre de lecture : saute à une position du morceau.
    func seek(seconds: TimeInterval) {
        guard let track else { return }
        let target = min(max(0, seconds), max(track.duration - 0.5, 0))
        clock.jump(to: target)
        refreshCurrentLine()
        monitor.seek(to: target)
    }

    /// Mode « recaler » : le prochain clic sur une ligne indique ce qu'on entend en ce moment.
    private(set) var calibrating = false

    func startCalibration() { calibrating = true }
    func cancelCalibration() { calibrating = false }

    /// Clic sur une ligne : Musique repart au début de ce passage
    /// (ou, en mode recalage, la ligne devient celle chantée maintenant).
    func seek(to line: LyricLine) {
        guard let time = line.time, track != nil else { return }
        if calibrating {
            calibrating = false
            setSongOffset(time - livePosition - Preferences.syncOffset + 0.05)
            refreshCurrentLine()
            return
        }
        let target = max(0, time - songOffset)
        clock.jump(to: target)
        refreshCurrentLine()
        monitor.seek(to: target)
    }

    // MARK: Vérification de la synchro

    /// Le timing des paroles colle-t-il à la durée du morceau ?
    var syncCheck: SyncCheck? {
        guard let track, let lyrics, !lyrics.isInstrumental else { return nil }
        return lyrics.syncCheck(duration: track.duration)
    }

    /// Décalage propre au morceau en cours (s'ajoute au réglage général).
    private(set) var songOffset: Double = 0
    private(set) var searchingVersion = false
    /// « version 2 sur 5 » après avoir essayé une autre version.
    private(set) var versionInfo: (index: Int, count: Int)?
    @ObservationIgnored private var versions: [Lyrics] = []

    func setSongOffset(_ value: Double) {
        guard let track else { return }
        songOffset = (value * 10).rounded() / 10
        LyricsStore.saveOffset(songOffset, for: track)
    }

    /// Passe à la version suivante des paroles sur LRCLIB (album, radio edit, live…).
    func tryOtherVersion() {
        guard let track, let current = lyrics, !searchingVersion else { return }
        searchingVersion = true
        Task {
            defer { searchingVersion = false }
            if versions.isEmpty {
                versions = await lyricsStore.allVersions(for: track)
            }
            guard currentTrackID == track.id, !versions.isEmpty else { return }
            let start = versions.firstIndex { $0.fullText == current.fullText } ?? -1
            let next = (start + 1) % versions.count
            let chosen = versions[next]
            versionInfo = (next + 1, versions.count)
            guard chosen.fullText != current.fullText else { return }
            lyricsStore.replace(chosen, for: track)
            lyricsStatus = .loaded(chosen)
            retranslate()
        }
    }

    var engine: TranslationEngine {
        TranslationEngine(rawValue: UserDefaults.standard.string(forKey: SettingsKey.engine) ?? "") ?? .apple
    }

    init() {
        artworkService = ArtworkService(runner: monitor.runner)
        nextTrackPredictor = NextTrackPredictor(runner: monitor.runner)
        monitor.onUpdate = { [weak self] state in self?.handle(state) }
        if !ecoMode { startWork() } else { installEcoWake(); wakeIfMusicAlreadyPlaying() }
        // Nettoyage du cache au lancement puis une fois par jour.
        maintenanceTask = Task {
            while !Task.isCancelled {
                _ = await CacheManager.shared.prune(limitMB: Preferences.cacheLimitMB,
                                                    maxAgeDays: Preferences.cacheMaxAgeDays)
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    // MARK: Mode éco

    /// Mode éco : l'app reste dans la barre des menus mais ne fait plus rien
    /// (plus de lecture de Musique, d'horloge, de traduction ni de préchargement).
    /// Pas gardé d'un lancement à l'autre : l'app démarre active, sauf réglage « Démarrer en mode éco ».
    private(set) var ecoMode = Preferences.ecoAtLaunch

    /// `wakeOnMusic` : mode éco automatique, qui repart en lecteur dès que la musique reprend.
    func setEcoMode(_ on: Bool, wakeOnMusic: Bool = false) {
        guard on != ecoMode else { return }
        ecoMode = on
        if on { if wakeOnMusic { installEcoWake() } } else { removeEcoWake() }
        if on {
            monitor.stop()
            ticker?.cancel(); ticker = nil
            loadTask?.cancel(); artworkTask?.cancel(); prefetchTask?.cancel()
            currentTrackID = nil
            playback = .stopped
            lyricsStatus = .idle
            translationStatus = .idle
            sourceLanguage = nil
            artwork = nil
            artworkID = nil
            currentLineIndex = nil
            calibrating = false
        } else {
            lastMusic = .now
            startWork()
        }
    }

    /// Écoute la notification de Musique (aucun coût au repos) pour sortir du mode éco quand la lecture reprend.
    private func installEcoWake() {
        guard ecoWakeObserver == nil else { return }
        ecoWakeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] note in
            guard (note.userInfo?["Player State"] as? String) == "Playing" else { return }
            MainActor.assumeIsolated { self?.wakeFromEcoForMusic() }
        }
    }

    /// « Démarrer en mode éco » alors que Musique joue déjà : la notification « Playing » est passée
    /// avant le lancement et ne reviendra qu'au prochain play ou changement de morceau.
    /// Une seule lecture de Musique (rien si elle est fermée) pour se réveiller tout de suite.
    private func wakeIfMusicAlreadyPlaying() {
        Task {
            guard await monitor.runner.poll().isPlaying else { return }
            wakeFromEcoForMusic()
        }
    }

    private func removeEcoWake() {
        if let ecoWakeObserver { DistributedNotificationCenter.default().removeObserver(ecoWakeObserver) }
        ecoWakeObserver = nil
    }

    /// De la musique repart pendant le mode éco : on revient, en lecteur (qui consomme très peu).
    private func wakeFromEcoForMusic() {
        guard ecoMode else { return }
        if !bubbleCompact { setBubbleCompact(true) }
        lastMusic = .now
        lastUse = .now
        setEcoMode(false)
    }

    /// Sans musique pendant ce temps (bulle fermée) : mode éco.
    static let ecoAfterSilence: TimeInterval = 15 * 60

    /// Paroles affichées (ni mode éco, ni lecteur réduit).
    var showsLyrics: Bool { !ecoMode && !bubbleCompact }

    /// Clic droit « Paroles + traduction » : sort du mode éco ou du lecteur, et traduit tout de suite
    /// (sans passer par la pilule EN → FR).
    func showLyricsAndTranslate() {
        if translationHidden { setTranslationHidden(false) }
        lastUse = .now
        if ecoMode {
            translateNextTrack = true          // le morceau sera relu au réveil
            if bubbleCompact { setBubbleCompact(false) }
            setEcoMode(false)
        } else {
            translationRequested = true
            if bubbleCompact { setBubbleCompact(false) } else { retranslate() }
        }
    }

    private func startWork() {
        monitor.setVisible(visibleViews > 0)
        monitor.start()
        startTicker()
    }

    /// Horloge locale des paroles : 50 ms en lecture synchronisée affichée, 500 ms à l'écran,
    /// 30 s quand rien n'est affiché (juste pour la mise en veille automatique).
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Bulle fermée :
                // - pas de musique depuis 15 min → mode éco (zéro conso, réveil en lecteur à la reprise) ;
                // - musique, paroles pas regardées depuis le délai choisi → le lecteur.
                if self.playback.isPlaying { self.lastMusic = .now }
                if self.visibleViews == 0 {
                    if !self.playback.isPlaying, Date.now.timeIntervalSince(self.lastMusic) > Self.ecoAfterSilence {
                        self.setEcoMode(true, wakeOnMusic: true)
                        return
                    }
                    let idle = Double(Preferences.autoEcoMinutes) * 60
                    if idle > 0, self.playback.isPlaying, !self.bubbleCompact,
                       Date.now.timeIntervalSince(self.lastUse) > idle {
                        self.setBubbleCompact(true)
                    }
                }
                guard self.visibleViews > 0 else {
                    // Rien à l'écran : inutile de suivre la ligne chantée (réveil par viewAppeared).
                    try? await Task.sleep(for: .seconds(30))
                    continue
                }
                if self.bubbleCompact {
                    // Lecteur réduit : pas de paroles à suivre (la barre de lecture a sa propre horloge).
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                self.refreshCurrentLine()
                // 20 fois par seconde seulement quand on regarde des paroles synchronisées.
                let fast = self.playback.isPlaying && self.lyrics?.isSynced == true
                try? await Task.sleep(for: .milliseconds(fast ? 50 : 500))
            }
        }
    }

    /// Les titres favoris gardent paroles, traduction et pochette même quand le cache est plein.
    private func updateFavoriteProtection() {
        guard let track, let lyrics else { return }
        let favorite = isFavorited
        let translationKey = TranslationStore.key(track, lyrics, engine)
        let lyricsKey = LyricsStore.key(for: track)
        let signature = "\(track.id)|\(favorite)|\(translationKey)|\(translations != nil)"
        guard signature != protectionSignature else { return }
        protectionSignature = signature
        CacheManager.shared.setProtected(favorite, song: lyricsKey,
                                         cacheKeys: [lyricsKey, translationKey, "\(track.artist)|\(track.album)"])
    }

    var isFavorited: Bool {
        guard let track else { return false }
        if let o = favoriteOverride, o.id == track.id { return o.value }
        return track.isFavorited
    }

    func toggleFavorite() {
        guard let track else { return }
        let newValue = !isFavorited
        favoriteOverride = (track.id, newValue)
        favoriteError = nil
        Task {
            if let error = await monitor.runner.setFavorited(newValue) {
                favoriteOverride = nil
                favoriteError = "Impossible de modifier le favori : \(error)"
                try? await Task.sleep(for: .seconds(4))
                favoriteError = nil
            }
        }
    }

    private func handle(_ state: PlaybackState) {
        guard !ecoMode else { return }   // lecture partie juste avant le passage en éco
        clock.update(with: state, sameTrack: state.track?.id == currentTrackID)
        if state.withoutPosition != playback.withoutPosition { playback = state }
        if let o = favoriteOverride, state.track?.id != o.id || state.track?.isFavorited == o.value {
            favoriteOverride = nil   // Musique a confirmé (ou le morceau a changé)
        }
        defer { updateFavoriteProtection() }
        let id = state.track?.id
        guard id != currentTrackID else { return }
        currentTrackID = id
        loadTask?.cancel()
        lyricsStatus = .idle
        translationStatus = .idle
        sourceLanguage = nil
        versions = []
        versionInfo = nil
        calibrating = false
        translationRequested = translateNextTrack
        translateNextTrack = false
        songOffset = state.track.map(LyricsStore.savedOffset(for:)) ?? 0
        artworkTask?.cancel()
        if let track = state.track {
            // Lecteur réduit : sobre comme le mode éco, pas de paroles (chargées au dépliage).
            if !bubbleCompact { loadTask = Task { await load(track) } }
            artworkTask = Task {
                let data = await artworkService.artwork(for: track)
                guard !Task.isCancelled, currentTrackID == track.id else { return }
                artwork = data.flatMap(NSImage.init(data:))
                artworkID = track.id
                // Après l'animation, retour au sens normal (enchaînement auto = par la droite).
                try? await Task.sleep(for: .milliseconds(700))
                if !Task.isCancelled { artworkFromLeading = false }
            }
        } else {
            artwork = nil
            artworkID = nil
        }
    }

    // MARK: Lecture

    func send(_ command: PlayerCommand) {
        // Le sens est fixé AVANT le changement de pochette : l'ancienne pochette doit déjà
        // porter la bonne transition au moment où elle sort.
        if command == .previous { artworkFromLeading = true }
        if command == .next { artworkFromLeading = false }
        monitor.send(command)
    }

    // MARK: Paroles

    private func load(_ track: TrackInfo) async {
        if let cached = lyricsStore.cached(track) {
            lyricsStatus = .loaded(cached)
            await refreshIfDoubtful(cached, track: track)
            guard !Task.isCancelled else { return }
        } else {
            lyricsStatus = .loading
            do {
                let result = try await lyricsStore.fetch(track)
                guard !Task.isCancelled else { return }
                guard let result else { lyricsStatus = .notFound; return }
                lyricsStatus = .loaded(result)
            } catch {
                guard !Task.isCancelled else { return }
                lyricsStatus = .failed(error.localizedDescription)
                return
            }
        }
        await translate(track)
        guard !Task.isCancelled else { return }
        prefetchNext(after: track)
    }

    /// Paroles en cache douteuses : une fois par session, on regarde si LRCLIB a mieux
    /// et on l'affiche si le morceau est toujours celui en cours.
    private func refreshIfDoubtful(_ cached: Lyrics, track: TrackInfo) async {
        guard let fresh = await lyricsStore.betterVersionIfDoubtful(cached, track: track),
              !Task.isCancelled, currentTrackID == track.id else { return }
        lyricsStore.replace(fresh, for: track)
        lyricsStatus = .loaded(fresh)
    }

    // MARK: Traduction

    /// Relance la traduction du morceau en cours (changement de moteur, langue téléchargée…).
    func retranslate() {
        guard let track, lyrics != nil else { return }
        loadTask?.cancel()
        loadTask = Task { await translate(track) }
    }

    /// Pilule « EN → FR » barrée : aucune traduction, paroles originales seules (re-clic : on retraduit).
    private(set) var translationHidden = UserDefaults.standard.bool(forKey: SettingsKey.translationHidden)

    /// Traduction demandée à la main pour le son en cours (clic sur la pilule quand la traduction auto est coupée).
    private(set) var translationRequested = false

    /// La traduction du son en cours est-elle affichée (ou en route) ?
    var translationShown: Bool {
        switch translationStatus {
        case .translating, .partial, .done: true
        default: false
        }
    }

    /// Clic sur la pilule « EN → FR » :
    /// pas encore traduit → traduit ; traduction affichée → barrée (original seul) ; barrée → réaffichée.
    func languagePillTapped() {
        if translationHidden {
            setTranslationHidden(false)
            translationRequested = true
            retranslate()
        } else if translationShown {
            setTranslationHidden(true)
            // Arrête une traduction en cours (seulement si les paroles sont déjà là, pour ne pas couper leur chargement).
            if lyrics != nil { loadTask?.cancel() }
            translationStatus = .idle
        } else {
            translationRequested = true
            retranslate()
        }
    }

    private func setTranslationHidden(_ hidden: Bool) {
        translationHidden = hidden
        UserDefaults.standard.set(hidden, forKey: SettingsKey.translationHidden)
    }

    /// Bulle repliée (juste l'en-tête et les commandes) : paroles cachées, donc rien n'est traduit.
    private(set) var bubbleCompact = UserDefaults.standard.bool(forKey: SettingsKey.bubbleCompact)

    func toggleBubbleCompact() { setBubbleCompact(!bubbleCompact) }

    private func setBubbleCompact(_ on: Bool) {
        guard on != bubbleCompact else { return }
        bubbleCompact = on
        UserDefaults.standard.set(bubbleCompact, forKey: SettingsKey.bubbleCompact)
        if bubbleCompact {
            // Lecteur réduit = sobre comme le mode éco : plus de paroles, de traduction ni de préchargement.
            loadTask?.cancel()
            prefetchTask?.cancel()
            if lyrics == nil { lyricsStatus = .idle }
        } else if let track, lyrics == nil {
            loadTask = Task { await load(track) }   // morceaux changés pendant le lecteur : paroles à charger
        } else {
            retranslate()   // paroles de retour : traduction en cache ou à faire (selon la pilule)
        }
    }

    /// Réglage « Traduire automatiquement » activé : on traduit tout de suite le son en cours.
    func autoTranslateChanged() {
        if Preferences.autoTranslate, !translationHidden { retranslate() }
    }

    /// Bibliothèque des sons déjà traduits (pilule disque dur) : remplace les paroles par la liste.
    var libraryOpen = false

    /// Langue vers laquelle on traduit le morceau en cours.
    var translationTarget: Locale.Language {
        sourceLanguage?.isFrench == true && Preferences.frenchToEnglish ? .english : .french
    }

    /// Réglage « chansons en français → anglais » changé : on retraduit si le son en cours est en français.
    func frenchToEnglishChanged() {
        guard sourceLanguage?.isFrench == true else { return }
        retranslate()
    }

    private func translate(_ track: TrackInfo) async {
        guard let lyrics, !lyrics.isInstrumental else { return }
        let engine = self.engine
        sourceLanguage = LanguageDetector.detect(lyrics.fullText)
        let target = translationTarget
        // Traduction désactivée (pilule barrée) ou paroles cachées (bulle repliée) : rien à traduire.
        if bubbleCompact {
            translationStatus = .idle
            return
        }
        if translationHidden, sourceLanguage?.isFrench != true {
            translationStatus = .idle
            return
        }
        if let cached = translationStore.cached(track, lyrics: lyrics, engine: engine,
                                                target: target, source: sourceLanguage) {
            translationStatus = .done(cached)   // déjà traduit : affiché directement
            return
        }
        // Traduction à la demande (par défaut) : on attend le clic sur la pilule.
        if !Preferences.autoTranslate, !translationRequested, sourceLanguage?.isFrench != true {
            translationStatus = .idle
            return
        }
        if sourceLanguage.map({ $0.sameLanguage(as: target) }) != true { translationStatus = .translating }

        do {
            let outcome = try await translationStore.fetch(track, lyrics: lyrics, engine: engine, target: target) { [weak self] line, text in
                self?.showPartial(trackID: track.id, line: line, text: text, count: lyrics.lines.count)
            }
            guard !Task.isCancelled, currentTrackID == track.id else { return }
            switch outcome {
            case .french: translationStatus = .alreadyFrench
            case .translated(let lines): translationStatus = .done(lines)
            }
        } catch TranslationFailure.needsDownload(let lang) {
            translationStatus = .needsDownload(lang, target)
        } catch {
            guard !Task.isCancelled else { return }
            translationStatus = .failed(error.localizedDescription)
        }
    }

    /// Affiche une ligne traduite dès qu'elle arrive.
    private func showPartial(trackID: String, line: Int, text: String, count: Int) {
        guard currentTrackID == trackID else { return }
        var lines: [String]
        switch translationStatus {
        case .translating: lines = Array(repeating: "", count: count)
        case .partial(let current): lines = current
        default: return
        }
        guard lines.indices.contains(line) else { return }
        lines[line] = text
        translationStatus = .partial(lines)
    }

    // MARK: Préchargement

    /// Prépare paroles et traduction du morceau suivant pendant que celui-ci joue.
    private func prefetchNext(after track: TrackInfo) {
        prefetchTask?.cancel()
        guard Preferences.prefetchNext, !bubbleCompact else { return }
        let engine = self.engine
        prefetchTask = Task {
            guard let next = await nextTrackPredictor.next(after: track), !Task.isCancelled else {
                Self.log.info("Préchargement : morceau suivant inconnu après « \(track.title, privacy: .public) »")
                return
            }
            Self.log.info("Préchargement : « \(next.title, privacy: .public) » (\(next.artist, privacy: .public))")
            do {
                guard let lyrics = try await lyricsStore.fetch(next), !lyrics.isInstrumental else {
                    Self.log.info("Préchargement : pas de paroles pour « \(next.title, privacy: .public) »")
                    return
                }
                // Traduction coupée ou à la demande : on ne prépare que les paroles.
                if self.translationHidden || self.bubbleCompact || !Preferences.autoTranslate { return }
                _ = try await translationStore.fetch(next, lyrics: lyrics, engine: engine)
                Self.log.info("Préchargement terminé : « \(next.title, privacy: .public) » est en cache")
            } catch {
                Self.log.error("Préchargement échoué : \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
