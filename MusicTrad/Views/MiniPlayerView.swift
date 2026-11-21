import AVFoundation
import SwiftUI

/// Bulle repliée : petit lecteur carré. Pochette en grand sur un fond tiré de la pochette,
/// titre, artiste, progression et commandes. Pas de paroles, donc rien n'est traduit.
/// Avec une pochette animée, la vidéo prend tout le carré (comme le lecteur plein écran de l'iPhone).
struct MiniPlayerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var hoveringArtist = false
    /// Souris sur le lecteur : voile sombre sur la pochette animée pour bien voir les commandes.
    @State private var hovering = false
    @AppStorage(SettingsKey.animatedArtwork) private var animated = false
    /// Vidéo de la pochette animée, et le morceau auquel elle correspond.
    @State private var motionURL: URL?
    @State private var motionKey: String?

    static let side: CGFloat = 320
    private var side: CGFloat { Self.side }
    private let cover: CGFloat = 136

    var body: some View {
        ZStack {
            if let motionURL { fullBleed(motionURL) } else { background }
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    AirPlayButton()
                    Spacer()
                    AppButtons()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                if motionURL == nil {
                    Spacer(minLength: 4)
                    artwork
                    Spacer(minLength: 10)
                } else {
                    // La vidéo occupe le carré : la zone vide ouvre l'album.
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { openAlbum() }
                        .pointerStyle(.link)
                        .help("Ouvrir l'album dans Musique")
                }

                titles

                ProgressLine()
                    .padding(.horizontal, 26)
                    .padding(.top, 8)

                PlaybackControls(size: 17, showsExtras: false)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: side, height: side)
        .onHover { over in withAnimation(.easeInOut(duration: 0.2)) { hovering = over } }
        .task(id: "\(albumKey)|\(animated)|\(app.isOnScreen)") { await loadMotion() }
    }

    private var titles: some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                Text(app.track?.title ?? "Rien en lecture")
                    .font(.headline)
                    .lineLimit(1)
                if app.track != nil { FavoriteButton() }
            }
            Text(app.track?.artist ?? " ")
                .font(.callout)
                .foregroundStyle(motionURL == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white.opacity(0.8)))
                .lineLimit(1)
                .underline(hoveringArtist)
                .onHover { hoveringArtist = $0 && app.track != nil }
                .onTapGesture {
                    guard app.track != nil else { return }
                    dismiss()
                    app.openArtist()
                }
                .pointerStyle(app.track == nil ? nil : .link)
        }
        .shadow(color: .black.opacity(motionURL == nil ? 0 : 0.5), radius: 6)
        .padding(.horizontal, 24)
    }

    private func openAlbum() {
        guard app.track != nil else { return }
        dismiss()
        app.openAlbum()
    }

    /// La pochette animée est celle de l'album : un son suivant du même album garde la vidéo, sans transition.
    private var albumKey: String {
        guard let track = app.track else { return "" }
        return "\(track.artist)|\(track.album)".normalizedForMatch
    }

    /// Cherche la pochette animée de l'album, seulement quand la bulle est à l'écran (résultat en cache).
    private func loadMotion() async {
        guard app.isOnScreen else { return }
        let key = "\(albumKey)|\(animated)"
        guard key != motionKey else { return }
        withAnimation(.easeInOut(duration: 0.3)) { motionURL = nil }
        guard animated, app.track != nil else { motionKey = key; return }
        let url = await app.motionArtwork()
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.4)) { motionURL = url }
        motionKey = key
    }

    /// Pochette animée plein carré : la pochette fixe dessous le temps que la vidéo démarre,
    /// des dégradés pour lire les boutons et le texte. En pause : vidéo arrêtée et assombrie.
    private func fullBleed(_ url: URL) -> some View {
        let playing = app.playback.isPlaying
        return ZStack {
            LyricsPalette.background
            if let image = app.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
            }
            MotionArtworkView(url: url, playing: playing && app.isOnScreen, cornerRadius: 0)
                .frame(width: side, height: side)
                .allowsHitTesting(false)
            Color.black.opacity(playing ? 0 : 0.3)
                .animation(.easeInOut(duration: 0.3), value: playing)
            Color.black.opacity(hovering ? 0.35 : 0)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 70)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 170)
            }
            .allowsHitTesting(false)
        }
        .frame(width: side, height: side)
        .clipped()
        .transition(.opacity)
    }

    /// Fond : la pochette floutée et assombrie (noir si rien ne joue).
    @ViewBuilder
    private var background: some View {
        ZStack {
            LyricsPalette.background
            if let image = app.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .blur(radius: 40)
                    .opacity(0.55)
                    .id(app.artworkID)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        }
        .frame(width: side, height: side)
        .clipped()
        .animation(.easeInOut(duration: 0.5), value: app.artworkID)
    }

    private var artwork: some View {
        let playing = app.playback.isPlaying
        return ZStack {
            ArtworkView(image: app.artwork, size: cover)
                .id(app.artworkID)
                .transition(.push(from: app.artworkFromLeading ? .leading : .trailing))
        }
        .frame(width: cover, height: cover)
        .clipShape(.rect(cornerRadius: cover * 0.14))
        .shadow(color: .black.opacity(playing ? 0.55 : 0.3), radius: 14, y: 6)
        // En pause : grise et recule légèrement, comme dans Musique.
        .saturation(playing ? 1 : 0)
        .brightness(playing ? 0 : -0.08)
        .scaleEffect(playing ? 1 : 0.88)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: playing)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: app.artworkID)
        .contentShape(.rect)
        .onTapGesture { openAlbum() }
        .pointerStyle(app.track == nil ? nil : .link)
        .help("Ouvrir l'album dans Musique")
    }
}

/// Fine barre de progression avec le temps écoulé et restant, rafraîchie deux fois par seconde.
/// Clic ou glisser dessus : Musique saute à cet endroit.
private struct ProgressLine: View {
    @Environment(AppState.self) private var app
    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        // Arrêtée quand la bulle est fermée (la fenêtre reste vivante hors écran).
        TimelineView(.animation(minimumInterval: 0.5, paused: !app.isOnScreen)) { _ in
            let duration = app.track?.duration ?? 0
            let live = min(max(app.playerPosition, 0), max(duration, 0))
            let fraction = dragFraction ?? (duration > 0 ? live / duration : 0)
            let position = dragFraction.map { $0 * duration } ?? live
            let thick = hovering || dragFraction != nil
            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(Color.white.opacity(thick ? 1 : 0.85))
                            .frame(width: max(geo.size.width * fraction, thick ? 7 : 4))
                    }
                    .frame(height: thick ? 7 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard duration > 0 else { return }
                                dragFraction = Self.clamp(value.location.x / geo.size.width)
                            }
                            .onEnded { value in
                                guard duration > 0 else { return }
                                app.seek(seconds: Self.clamp(value.location.x / geo.size.width) * duration)
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 14)
                .onHover { hovering = $0 && duration > 0 }
                .animation(.snappy(duration: 0.15), value: thick)
                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text("-" + Self.format(max(duration - position, 0)))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .opacity(duration > 0 ? 1 : 0)
        }
    }

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Pochette animée : vidéo HLS d'Apple Music en boucle, muette, en basse résolution.
/// Invisible tant que la première image n'est pas prête (la pochette fixe reste dessous).
private struct MotionArtworkView: NSViewRepresentable {
    let url: URL
    let playing: Bool
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> MotionArtworkNSView { MotionArtworkNSView() }

    func updateNSView(_ view: MotionArtworkNSView, context: Context) {
        view.layer?.cornerRadius = cornerRadius
        view.load(url)
        view.setPlaying(playing)
    }

    static func dismantleNSView(_ view: MotionArtworkNSView, coordinator: ()) { view.stop() }
}

private final class MotionArtworkNSView: NSView {
    private let player = AVQueuePlayer()
    private let playerLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?
    private var readyObservation: NSKeyValueObservation?
    private var url: URL?
    private var wantsPlaying = false
    private var isRunning = false
    private var focusObservers: [NSObjectProtocol] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.opacity = 0
        layer?.addSublayer(playerLayer)
        readyObservation = playerLayer.observe(\.isReadyForDisplay) { [weak self] _, _ in
            Task { @MainActor in self?.readyChanged() }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// La vidéo ne tourne que si la bulle est au premier plan : une autre fenêtre ou une autre app
    /// au premier plan (ou la bulle cachée) la met en pause.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusObservers.forEach(NotificationCenter.default.removeObserver)
        focusObservers = []
        guard let window else { return }
        let names: [(Notification.Name, AnyObject?)] = [
            (NSWindow.didBecomeKeyNotification, window), (NSWindow.didResignKeyNotification, window),
            (NSWindow.didChangeOcclusionStateNotification, window),
            (NSApplication.didBecomeActiveNotification, NSApp), (NSApplication.didResignActiveNotification, NSApp),
        ]
        focusObservers = names.map { name, object in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyPlayback() }
            }
        }
        applyPlayback()
    }

    private var inFront: Bool {
        guard let window, window.occlusionState.contains(.visible) else { return false }
        return window.isKeyWindow || NSApp.isActive
    }

    private func applyPlayback() {
        let run = wantsPlaying && inFront && looper != nil
        guard run != isRunning else { return }
        isRunning = run
        if run { player.play() } else { player.pause() }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func load(_ new: URL) {
        guard new != url else { return }
        url = new
        playerLayer.opacity = 0
        let item = AVPlayerItem(url: new)
        item.preferredMaximumResolution = CGSize(width: 480, height: 480)
        item.preferredPeakBitRate = 1_500_000
        player.removeAllItems()
        looper = AVPlayerLooper(player: player, templateItem: item)
        isRunning = false
        applyPlayback()
    }

    func setPlaying(_ playing: Bool) {
        wantsPlaying = playing
        applyPlayback()
    }

    func stop() {
        focusObservers.forEach(NotificationCenter.default.removeObserver)
        focusObservers = []
        isRunning = false
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        readyObservation = nil
    }

    private func readyChanged() {
        guard playerLayer.isReadyForDisplay, playerLayer.opacity == 0 else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        playerLayer.opacity = 1
        CATransaction.commit()
    }
}

/// Fond « couleur de l'album » derrière les paroles : la pochette très floutée et assombrie,
/// en fondu d'un morceau à l'autre (comme le petit lecteur). Noir si rien ne joue.
struct AlbumBackdrop: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            LyricsPalette.background
            Color.clear.overlay {
                if let image = app.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 60)
                        .opacity(0.6)
                        .id(app.artworkID)
                        .transition(.opacity)
                }
            }
            .clipped()
            Color.black.opacity(0.45)
        }
        .animation(.easeInOut(duration: 0.8), value: app.artworkID)
        .allowsHitTesting(false)
    }
}

/// Fond de la bulle et de la fenêtre flottante, selon le réglage (noir ou couleur de l'album).
struct LyricsBackground: View {
    @Environment(AppState.self) private var app
    @AppStorage(SettingsKey.albumBackground) private var albumBackground = true

    var body: some View {
        if albumBackground && !app.ecoMode { AlbumBackdrop() } else { LyricsPalette.background }
    }
}
