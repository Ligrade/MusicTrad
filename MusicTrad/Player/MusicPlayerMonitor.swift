import AppKit
import Foundation

/// Lit l'état de l'app Musique par AppleScript.
/// Paroles affichées : toutes les 0,5 s. Rien à l'écran : Musique prévient elle-même
/// (notification « playerInfo » à chaque lecture, pause, arrêt ou changement de morceau) ;
/// on ne relit alors qu'à ce moment-là, plus une fois par minute par sécurité.
final class MusicPlayerMonitor {
    var onUpdate: ((PlaybackState) -> Void)?
    private var task: Task<Void, Never>?
    let runner = AppleScriptRunner()
    private var observer: MusicNotificationObserver?
    /// Vrai quand la bulle ou la fenêtre flottante est à l'écran.
    private(set) var isVisible = false

    /// Rythme de lecture : rapide quand les paroles sont affichées, filet de sécurité sinon.
    private var interval: Duration { isVisible ? .milliseconds(500) : .seconds(60) }

    func start() {
        guard task == nil else { return }
        observer = MusicNotificationObserver(
            onChange: { [weak self] in self?.pollNow() },
            onQuit: { [weak self] in
                // Pas de relecture : « tell application "Music" » relancerait l'app.
                guard let self, self.task != nil else { return }
                self.onUpdate?(.musicNotRunning)
            })
        restartLoop()
    }

    func stop() {
        observer?.invalidate()
        observer = nil
        task?.cancel()
        task = nil
        polling = false
        pendingPoll = false
    }

    /// Paroles affichées ou non : à l'ouverture, lecture immédiate puis toutes les 0,5 s.
    /// En passant en arrière-plan, la boucle finit son attente de 0,5 s puis ralentit d'elle-même.
    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible { pollNow() }
    }

    /// Relit Musique tout de suite (notification reçue, vue ouverte…) puis reprend le rythme normal.
    func pollNow() {
        guard task != nil else { return }   // arrêté (mode éco) : on ignore
        // Musique envoie souvent plusieurs notifications d'affilée : une seule relecture de plus suffit.
        if polling { pendingPoll = true } else { restartLoop() }
    }

    /// Lecture AppleScript en cours, et relecture demandée pendant celle-ci.
    private var polling = false
    private var pendingPoll = false

    private func restartLoop() {
        task?.cancel()
        polling = false
        pendingPoll = false
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.pendingPoll = false
                self.polling = true
                let state = await self.runner.poll()
                guard !Task.isCancelled else { return }   // arrêtée ou relancée entre-temps
                self.polling = false
                self.onUpdate?(state)
                if self.pendingPoll { continue }
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    /// Envoie une commande à Musique puis relit l'état aussitôt.
    func send(_ command: PlayerCommand) {
        Task { [weak self] in
            guard let self else { return }
            await self.runner.run(command)
            self.onUpdate?(await self.runner.poll())
        }
    }
}

/// Écoute Musique sans l'interroger : notification « playerInfo » (lecture, pause, morceau…)
/// et lancement / fermeture de l'app.
private final class MusicNotificationObserver: NSObject {
    private static let bundleID = "com.apple.Music"
    private let onChange: () -> Void
    private let onQuit: () -> Void

    init(onChange: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onChange = onChange
        self.onQuit = onQuit
        super.init()
        // `.deliverImmediately` : une app de barre des menus est presque toujours inactive,
        // et la livraison serait sinon retardée jusqu'à ce qu'elle redevienne active.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(playerInfo(_:)),
            name: Notification.Name("com.apple.Music.playerInfo"), object: nil,
            suspensionBehavior: .deliverImmediately)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(launched(_:)),
                              name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(terminated(_:)),
                              name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    func invalidate() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private static func isMusic(_ note: Notification) -> Bool {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == bundleID
    }

    @objc private func playerInfo(_ note: Notification) { onChange() }

    @objc private func launched(_ note: Notification) {
        if Self.isMusic(note) { onChange() }
    }

    @objc private func terminated(_ note: Notification) {
        if Self.isMusic(note) { onQuit() }
    }
}

extension MusicPlayerMonitor {
    /// Saute à une position puis relit l'état aussitôt.
    func seek(to seconds: TimeInterval) {
        Task { [weak self] in
            guard let self else { return }
            await self.runner.seek(to: seconds)
            self.onUpdate?(await self.runner.poll())
        }
    }
}

nonisolated struct AirPlayDevice: Identifiable, Hashable, Sendable {
    let name: String
    let kind: String
    let selected: Bool
    let available: Bool
    var id: String { name }
    var isComputer: Bool { kind == "computer" }

    var symbol: String {
        switch kind {
        case "computer": "laptopcomputer"
        case "Apple TV": "appletv"
        case "HomePod": "homepod"
        case "Bluetooth device": "headphones"
        default: "hifispeaker"
        }
    }
}

nonisolated enum PlayerCommand: String, Sendable {
    case previous = "back track"     // comme le bouton ⏮ de Musique : début du morceau, puis précédent
    case playPause = "playpause"
    case next = "next track"
}

/// Exécute le script sur une file dédiée pour ne jamais bloquer l'interface.
nonisolated final class AppleScriptRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "fr.dynamicagence.MusicTrad.applescript")
    private var script: NSAppleScript?

    // Noms de variables longs : « st », « nd », « rd » et « th » sont des mots réservés (1st, 2nd…).
    private static let source = """
    tell application "Music"
        set playerStateText to player state as text
        if playerStateText is "stopped" then return {playerStateText}
        try
            set currentTrackRef to current track
            set trackPID to ""
            try
                set trackPID to persistent ID of currentTrackRef
            end try
            set trackDuration to 0
            try
                set trackDuration to duration of currentTrackRef
            end try
            set isFavorite to false
            try
                set isFavorite to favorited of currentTrackRef
            end try
            return {playerStateText, name of currentTrackRef, artist of currentTrackRef, album of currentTrackRef, trackDuration, player position, trackPID, isFavorite}
        on error
            return {playerStateText}
        end try
    end tell
    """

    private var commandScripts: [PlayerCommand: NSAppleScript] = [:]

    func run(_ command: PlayerCommand) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                let script = self.commandScripts[command] ?? {
                    let s = NSAppleScript(source: "tell application \"Music\" to \(command.rawValue)")!
                    s.compileAndReturnError(nil)
                    self.commandScripts[command] = s
                    return s
                }()
                script.executeAndReturnError(nil)
                cont.resume()
            }
        }
    }

    /// Sorties AirPlay connues de Musique (Mac, enceintes, Apple TV…).
    func airPlayDevices() async -> [AirPlayDevice] {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.Music" }) else {
            return []
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<[AirPlayDevice], Never>) in
            queue.async {
                let source = """
                tell application "Music"
                    set deviceList to {}
                    repeat with airDevice in AirPlay devices
                        set end of deviceList to {name of airDevice, (kind of airDevice) as text, selected of airDevice, available of airDevice}
                    end repeat
                    return deviceList
                end tell
                """
                var error: NSDictionary?
                guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else {
                    cont.resume(returning: []); return
                }
                var devices: [AirPlayDevice] = []
                if result.numberOfItems > 0 {
                    for i in 1...result.numberOfItems {
                        guard let d = result.atIndex(i), d.numberOfItems >= 4 else { continue }
                        devices.append(AirPlayDevice(
                            name: d.atIndex(1)?.stringValue ?? "?",
                            kind: d.atIndex(2)?.stringValue ?? "",
                            selected: d.atIndex(3)?.booleanValue ?? false,
                            available: d.atIndex(4)?.booleanValue ?? false))
                    }
                }
                cont.resume(returning: devices)
            }
        }
    }

    /// Choisit la sortie : seule (`exclusive`) ou ajoutée / retirée du groupe.
    func selectAirPlay(_ name: String, exclusive: Bool, selected: Bool = true) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let command = exclusive
                    ? "set current AirPlay devices to {AirPlay device \"\(escaped)\"}"
                    : "set selected of AirPlay device \"\(escaped)\" to \(selected)"
                NSAppleScript(source: "tell application \"Music\" to \(command)")?.executeAndReturnError(nil)
                cont.resume()
            }
        }
    }

    /// Montre le morceau en cours dans Musique (solution de secours si l'album n'est pas trouvé).
    func revealCurrentTrack() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                NSAppleScript(source: "tell application \"Music\"\nreveal current track\nactivate\nend tell")?
                    .executeAndReturnError(nil)
                cont.resume()
            }
        }
    }

    /// Joue un son de la bibliothèque Musique (titre + artiste). Renvoie false s'il n'y est pas.
    func play(title: String, artist: String) async -> Bool {
        func quoted(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let source = """
        tell application "Music"
            set found to (every track of library playlist 1 whose name is \(quoted(title)) and artist is \(quoted(artist)))
            if found is {} then set found to (every track of library playlist 1 whose name is \(quoted(title)))
            if found is {} then return "no"
            play item 1 of found
            return "ok"
        end tell
        """
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            queue.async {
                let result = NSAppleScript(source: source)?.executeAndReturnError(nil).stringValue
                cont.resume(returning: result == "ok")
            }
        }
    }

    /// Lance la playlist des morceaux likés (son nom dépend de la langue de Musique).
    func playFavorites() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                NSAppleScript(source: """
                tell application "Music"
                    repeat with n in {"Morceaux préférés", "Favourite Songs", "Favorite Songs", "Titres favoris"}
                        if exists playlist n then
                            play playlist n
                            return
                        end if
                    end repeat
                end tell
                """)?.executeAndReturnError(nil)
                cont.resume()
            }
        }
    }

    /// Place la lecture de Musique à une position donnée (en secondes).
    func seek(to seconds: TimeInterval) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                let source = String(format: "tell application \"Music\" to set player position to %.2f", max(0, seconds))
                NSAppleScript(source: source)?.executeAndReturnError(nil)
                cont.resume()
            }
        }
    }

    /// Ajoute ou retire le morceau en cours des favoris de Musique (playlist « Titres favoris »).
    func setFavorited(_ value: Bool) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            queue.async {
                let script = NSAppleScript(source: "tell application \"Music\" to set favorited of current track to \(value)")
                var error: NSDictionary?
                script?.executeAndReturnError(&error)
                cont.resume(returning: error.map { $0[NSAppleScript.errorMessage] as? String ?? "Erreur AppleScript" })
            }
        }
    }

    private var nextScript: NSAppleScript?

    /// Morceau suivant de la playlist en cours (hors lecture aléatoire), si Musique l'expose.
    func nextInPlaylist() async -> TrackInfo? {
        await withCheckedContinuation { (cont: CheckedContinuation<TrackInfo?, Never>) in
            queue.async {
                if self.nextScript == nil {
                    let s = NSAppleScript(source: """
                    tell application "Music"
                        try
                            if shuffle enabled then return {}
                            set playlistRef to current playlist
                            set trackIndex to index of current track
                            set nextTrackRef to track (trackIndex + 1) of playlistRef
                            return {name of nextTrackRef, artist of nextTrackRef, album of nextTrackRef, duration of nextTrackRef}
                        end try
                        return {}
                    end tell
                    """)
                    s?.compileAndReturnError(nil)
                    self.nextScript = s
                }
                var error: NSDictionary?
                guard let r = self.nextScript?.executeAndReturnError(&error), r.numberOfItems == 4,
                      let title = r.atIndex(1)?.stringValue, !title.isEmpty else {
                    cont.resume(returning: nil); return
                }
                let artist = r.atIndex(2)?.stringValue ?? ""
                cont.resume(returning: TrackInfo(id: "prédit|\(title)", title: title, artist: artist,
                                                 album: r.atIndex(3)?.stringValue ?? "",
                                                 duration: r.atIndex(4)?.doubleValue ?? 0))
            }
        }
    }

    private var artworkScript: NSAppleScript?

    /// Pochette du morceau en cours (données PNG/JPEG), nil s'il n'y en a pas.
    func artworkData() async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            queue.async {
                if self.artworkScript == nil {
                    let s = NSAppleScript(source: """
                    tell application "Music"
                        try
                            -- Morceau en streaming : Musique garde souvent la pochette du précédent.
                            if class of current track is URL track then return ""
                            return raw data of artwork 1 of current track
                        end try
                        return ""
                    end tell
                    """)
                    s?.compileAndReturnError(nil)
                    self.artworkScript = s
                }
                var error: NSDictionary?
                let data = self.artworkScript?.executeAndReturnError(&error).data
                cont.resume(returning: (data?.count ?? 0) > 100 ? data : nil)
            }
        }
    }

    func poll() async -> PlaybackState {
        let running = NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == "com.apple.Music" }
        guard running else { return .musicNotRunning }
        return await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: self.execute()) }
        }
    }

    private func execute() -> PlaybackState {
        var error: NSDictionary?
        if script == nil {
            let compiled = NSAppleScript(source: Self.source)
            guard compiled?.compileAndReturnError(&error) == true else {
                let msg = error?[NSAppleScript.errorMessage] as? String ?? "Script AppleScript invalide"
                return .error("Compilation du script : \(msg)")
            }
            script = compiled
        }
        guard let result = script?.executeAndReturnError(&error) else {
            let code = error?[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743 : accès refusé ; -1744 : autorisation requise mais non demandée
            if code == -1743 || code == -1744 { return .notAuthorized }
            if code == -600 { return .musicNotRunning } // app quittée entre-temps
            let msg = error?[NSAppleScript.errorMessage] as? String ?? "Erreur AppleScript \(code)"
            return .error(msg)
        }

        let state = result.atIndex(1)?.stringValue ?? "stopped"
        guard result.numberOfItems >= 7 else { return .stopped }

        let title = result.atIndex(2)?.stringValue ?? ""
        let artist = result.atIndex(3)?.stringValue ?? ""
        let album = result.atIndex(4)?.stringValue ?? ""
        let duration = result.atIndex(5)?.doubleValue ?? 0
        let position = result.atIndex(6)?.doubleValue ?? 0
        let pid = result.atIndex(7)?.stringValue ?? ""
        let favorited = result.numberOfItems >= 8 ? (result.atIndex(8)?.booleanValue ?? false) : false

        let track = TrackInfo(
            id: pid.isEmpty ? "\(artist)|\(title)" : pid,
            title: title, artist: artist, album: album, duration: duration, isFavorited: favorited
        )
        switch state {
        case "playing", "fast forwarding", "rewinding": return .playing(track, position: position)
        case "paused": return .paused(track, position: position)
        default: return .stopped
        }
    }
}
