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

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
}
