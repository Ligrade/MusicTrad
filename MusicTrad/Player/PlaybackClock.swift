import Foundation

/// Horloge locale de lecture : Musique n'est interrogée que toutes les 0,5 s,
/// la position est donc estimée entre deux lectures (dernière position lue + temps écoulé).
struct PlaybackClock {
    /// Dernière position lue dans Musique et l'instant de la lecture.
    private var anchor = (position: TimeInterval(0), at: Date(), playing: false)
    private var seekGuardUntil = Date.distantPast

    /// Position estimée maintenant : dernière position lue + temps écoulé depuis.
    var position: TimeInterval {
        anchor.playing ? anchor.position + Date().timeIntervalSince(anchor.at) : anchor.position
    }

    /// Nouvelle lecture de Musique.
    mutating func update(with state: PlaybackState, sameTrack: Bool) {
        let polled = state.position
        // Juste après un saut, une lecture partie avant le saut ne doit pas ramener en arrière.
        if sameTrack, Date() < seekGuardUntil, abs(polled - position) > 1 { return }
        if sameTrack, state.isPlaying, anchor.playing {
            // Petit écart (latence d'AppleScript) : on se rapproche en douceur de la position de Musique,
            // dans les deux sens. Avant, l'horloge ne reculait jamais et finissait légèrement en avance.
            let estimate = position
            let error = polled - estimate
            if abs(error) < 0.4 {
                anchor = (estimate + error * 0.3, Date(), true)
                return
            }
        }
        anchor = (polled, Date(), state.isPlaying)
    }

    /// Saut demandé par l'utilisateur : la position est prise tout de suite,
    /// et les lectures de Musique parties avant le saut sont ignorées pendant 1,5 s.
    mutating func jump(to target: TimeInterval) {
        anchor = (target, Date(), anchor.playing)
        seekGuardUntil = Date().addingTimeInterval(1.5)
    }
}
