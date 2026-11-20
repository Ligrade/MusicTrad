import Foundation

/// Morceau en cours dans Musique.
nonisolated struct TrackInfo: Equatable, Hashable, Sendable {
    let id: String          // persistent ID (ou titre+artiste à défaut)
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    var isFavorited: Bool = false
}

nonisolated enum PlaybackState: Equatable, Sendable {
    case musicNotRunning
    case stopped
    case notAuthorized
    case playing(TrackInfo, position: TimeInterval)
    case paused(TrackInfo, position: TimeInterval)
    case error(String)

    var track: TrackInfo? {
        switch self {
        case .playing(let t, _), .paused(let t, _): t
        default: nil
        }
    }

    var position: TimeInterval {
        switch self {
        case .playing(_, let p), .paused(_, let p): p
        default: 0
        }
    }

    /// Même état sans la position : la position change à chaque lecture et n'a pas besoin
    /// de redessiner l'interface (la ligne en cours vient d'une horloge locale).
    var withoutPosition: PlaybackState {
        switch self {
        case .playing(let t, _): .playing(t, position: 0)
        case .paused(let t, _): .paused(t, position: 0)
        default: self
        }
    }

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
}
