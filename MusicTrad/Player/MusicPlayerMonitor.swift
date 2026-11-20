import AppKit
import Foundation

/// Interroge l'app Musique par AppleScript toutes les 0,5 s.
final class MusicPlayerMonitor {
    var onUpdate: ((PlaybackState) -> Void)?
    private var task: Task<Void, Never>?
    let runner = AppleScriptRunner()

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let state = await self.runner.poll()
                self.onUpdate?(state)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
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
