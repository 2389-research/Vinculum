// The Linux rendering backend: draws a device-independent `MathScene` into a
// Silica (Cairo) bitmap and encodes a PNG. `VinculumLayout` (parser, engine,
// MATH/GSUB parsing) is platform-free and already runs here; this is the Linux
// counterpart of `MathSceneRenderer` + `MathImageRenderer`. Glyphs are drawn
// as FreeType outlines (filled paths) — Silica is the canvas — so any bundled
// MATH font renders without depending on FontConfig font matching.
#if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
import Foundation
import Silica
import SilicaCairo
import Cairo
import VinculumLayout

public enum MathSilicaRenderer {

    private static let resources = ["latinmodern-math", "texgyretermes-math",
                                    "texgyrepagella-math", "stixtwo-math", "firamath"]

    /// Render `latex` to PNG bytes with the given bundled font, or nil if the
    /// LaTeX is unsupported or the font can't be loaded.
    public static func renderPNG(latex: String, resource: String = "latinmodern-math",
                                 baseSize: CGFloat = 24, display: Bool = false) -> Data? {
        guard resources.contains(resource),
              let otf = Bundle.module.url(forResource: resource, withExtension: "otf")
                .flatMap({ try? Data(contentsOf: $0) }),
              let font = FreeTypeFont(bytes: otf) else { return nil }

        let upm = Int(font.unitsPerEm)
        let constants = MathTableParser.constants(from: otf, unitsPerEm: upm) ?? .latinModern

        let measure: MathTextMeasurer = { text, size, _ in
            var width: CGFloat = 0
            var inkTop: CGFloat = 0, inkBot: CGFloat = 0, anyInk = false
            for scalar in text.unicodeScalars {
                let gid = font.glyphIndex(scalar)
                width += font.advanceEm(glyph: gid) * size
                let (t, b) = font.inkExtentEm(glyph: gid)
                if t != b {   // non-empty glyph
                    inkTop = anyInk ? max(inkTop, t * size) : t * size
                    inkBot = anyInk ? min(inkBot, b * size) : b * size
                    anyInk = true
                }
            }
            let asc = font.ascentEm * size, desc = font.descentEm * size
            return GlyphMetrics(width: width, ascent: asc, descent: desc,
                                inkAscent: anyInk ? min(asc, inkTop) : asc,
                                inkDescent: anyInk ? inkBot : -desc)
        }

        let node = MathParser.parse(latex)
        guard MathParser.isFullySupported(node) else { return nil }
        let engine = MathLayoutEngine(
            services: MathFontServices(measure: measure, constants: constants),
            baseSize: display ? baseSize * 1.15 : baseSize)
        let scene = engine.layout(node, display: display)
        guard scene.width > 0, scene.height > 0 else { return nil }

        let pad: CGFloat = 4
        let w = Int((scene.width + pad * 2).rounded(.up))
        let h = Int((scene.ascent + scene.descent + pad * 2).rounded(.up))
        guard let surface = try? Cairo.Surface.Image(format: .argb32, width: w, height: h),
              let ctx = try? CairoContext(surface: surface, size: CGSize(width: w, height: h),
                                          flipped: true) else { return nil }

        ctx.fillColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.beginPath(); ctx.addRect(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        ctx.fillPath(using: .winding)

        // The Cairo image surface is y-down from the top-left; the scene is
        // y-up with the origin on the baseline. Map every scene point through
        // `Coords`: x → pad + x, y → baseline − y (baseline `ascent + pad`
        // below the top). FreeType outlines are y-up too, so they map the
        // same way.
        let coords = Coords(pad: pad, baseline: scene.ascent + pad)
        draw(scene, in: ctx, coords: coords, font: font, ink: CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        return encodePNG(surface)
    }

    /// Scene (y-up, baseline origin) → Cairo image (y-down, top-left) mapping.
    private struct Coords {
        let pad: CGFloat, baseline: CGFloat
        func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: pad + x, y: baseline - y) }
    }

    private static func color(_ c: MathColor?, _ ink: CGColor) -> CGColor {
        guard let c else { return ink }
        return CGColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    /// Fills a glyph's outline at scene pen position `(px, py)`.
    private static func fillGlyph(_ gid: UInt16, size: CGFloat, px: CGFloat, py: CGFloat,
                                  in ctx: CairoContext, coords: Coords, font: FreeTypeFont) {
        guard let ops = font.outline(glyph: gid, size: size), !ops.isEmpty else { return }
        ctx.beginPath()
        addPath(ops, in: ctx, coords: coords, dx: px, dy: py)
        ctx.fillPath(using: .winding)
    }

    /// Adds `ops` (scene-local, offset by `(dx, dy)`) to the current path,
    /// mapping every point through `coords`.
    private static func addPath(_ ops: [PathOp], in ctx: CairoContext, coords: Coords,
                                dx: CGFloat, dy: CGFloat) {
        for op in ops {
            switch op {
            case .move(let p): ctx.move(to: coords.map(dx + p.x, dy + p.y))
            case .line(let p): ctx.addLine(to: coords.map(dx + p.x, dy + p.y))
            case let .quad(t, k):
                ctx.addQuadCurve(to: coords.map(dx + t.x, dy + t.y), control: coords.map(dx + k.x, dy + k.y))
            case let .cubic(t, c1, c2):
                ctx.addCurve(to: coords.map(dx + t.x, dy + t.y),
                             control1: coords.map(dx + c1.x, dy + c1.y),
                             control2: coords.map(dx + c2.x, dy + c2.y))
            case .close: ctx.closePath()
            }
        }
    }

    private static func draw(_ scene: MathScene, in ctx: CairoContext, coords: Coords,
                             font: FreeTypeFont, ink: CGColor) {
        for element in scene.elements {
            switch element {
            case let .glyphs(text, size, _, origin, c):
                ctx.fillColor = color(c, ink)
                var penX = origin.x
                for scalar in text.unicodeScalars {
                    let gid = font.glyphIndex(scalar)
                    fillGlyph(gid, size: size, px: penX, py: origin.y, in: ctx, coords: coords, font: font)
                    penX += font.advanceEm(glyph: gid) * size
                }

            case let .glyph(id, size, origin, c):
                ctx.fillColor = color(c, ink)
                fillGlyph(id, size: size, px: origin.x, py: origin.y, in: ctx, coords: coords, font: font)

            case let .rule(rect, c):
                // The rule is a y-up rect; map its top-left corner (maxY) so
                // the y-down rect covers the same band.
                ctx.fillColor = color(c, ink)
                let tl = coords.map(rect.origin.x, rect.origin.y + rect.size.height)
                ctx.beginPath()
                ctx.addRect(CGRect(x: tl.x, y: tl.y, width: rect.size.width, height: rect.size.height))
                ctx.fillPath(using: .winding)

            case let .stroke(path, width, cap, join, c):
                ctx.strokeColor = color(c, ink)
                ctx.lineWidth = width
                ctx.lineCap = cap.cgLineCap
                ctx.lineJoin = join.cgLineJoin
                ctx.beginPath()
                addPath(path, in: ctx, coords: coords, dx: 0, dy: 0)
                ctx.strokePath()

            case .region:
                break
            }
        }
    }
}

private extension StrokeCap {
    var cgLineCap: CGLineCap { switch self { case .butt: return .butt; case .round: return .round; case .square: return .square } }
}
private extension StrokeJoin {
    var cgLineJoin: CGLineJoin { switch self { case .miter: return .miter; case .round: return .round; case .bevel: return .bevel } }
}
#endif
