import AppKit
import CoreImage

/// Pochette réduite et floutée une fois pour toutes, pour les fonds « couleur de l'album » :
/// une image toute prête coûte bien moins qu'un flou recalculé à chaque image affichée.
enum ArtworkBackdrop {
    private static let ciContext = CIContext()

    static func make(from image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let source = CIImage(cgImage: cg)
        let scale = 64 / max(source.extent.width, source.extent.height, 1)
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 5).cropped(to: small.extent)
        guard let out = ciContext.createCGImage(blurred, from: small.extent) else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
    }
}
