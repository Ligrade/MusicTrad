import AppKit

// Icône MusicTrad : plaque blanche, note rouge centrée.
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpace(name: CGColorSpace.displayP3)!
func c(_ h: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((h>>16)&255)/255, CGFloat((h>>8)&255)/255, CGFloat(h&255)/255, a])!
}

// Plaque macOS 824 px avec ombre douce
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let plate = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: c(0x000000, 0.28))
ctx.addPath(plate); ctx.setFillColor(c(0xFFFFFF)); ctx.fillPath()
ctx.restoreGState()

// Fond blanc très légèrement dégradé
ctx.saveGState()
ctx.addPath(plate); ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [c(0xFFFFFF), c(0xF1F1F3)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// Note rouge, centrée sur sa forme réelle
let cfg = NSImage.SymbolConfiguration(pointSize: 400, weight: .semibold)
let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
let h: CGFloat = 520
let w = h * note.size.width / note.size.height
let rect = CGRect(x: 512 - w / 2, y: 512 - h / 2, width: w, height: h)

// Masque de la note, puis dégradé rouge dedans
let mask = NSImage(size: rect.size, flipped: false) { r in note.draw(in: r); return true }
var maskRect = CGRect(origin: .zero, size: rect.size)
let cgMask = mask.cgImage(forProposedRect: &maskRect, context: nil, hints: nil)!
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: c(0xC0102E, 0.25))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.clip(to: rect, mask: cgMask)
let red = CGGradient(colorsSpace: space, colors: [c(0xFF5A6E), c(0xF0203E)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(red, start: CGPoint(x: 512, y: rect.maxY), end: CGPoint(x: 512, y: rect.minY), options: [])
ctx.endTransparencyLayer()
ctx.restoreGState()
ctx.restoreGState()

// Liseré gris très léger
ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1, dy: 1), cornerWidth: 185, cornerHeight: 185, transform: nil))
ctx.setStrokeColor(c(0x000000, 0.08)); ctx.setLineWidth(2); ctx.strokePath()

NSGraphicsContext.current?.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
