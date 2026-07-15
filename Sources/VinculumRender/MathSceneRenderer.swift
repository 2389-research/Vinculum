#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreText
import CoreGraphics
import VinculumLayout

/// Draws a device-independent `MathScene` into a CoreGraphics context — the
/// "how" that pairs with layout's "what". Glyph runs use the bundled math
/// font; `nil`-colored primitives take the theme ink; a `\color` element
/// carries its own resolved sRGB. The context is expected to be y-up (the
/// scene's convention).
public enum MathSceneRenderer {

    /// Draws `scene` into a y-up context with its baseline origin at `origin`.
    /// `font` MUST be the font the scene was measured with — glyph IDs and
    /// metrics are font-specific, so there is deliberately no default: a
    /// mismatched font would silently draw wrong glyphs.
    public static func draw(_ scene: MathScene, theme: MathTheme, in ctx: CGContext,
                            at origin: CGPoint, font: MathFont) {
        for element in scene.elements {
            switch element {
            case let .glyphs(text, size, mono, o, color):
                let ctFont: CTFont = mono
                    ? PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
                    : (font.ctFont(size: size) ?? PlatformFont.systemFont(ofSize: size) as CTFont)
                let attributed = NSAttributedString(string: text, attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: ctFont,
                    kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true])
                let line = CTLineCreateWithAttributedString(attributed)
                ctx.saveGState()
                ctx.setFillColor(cgColor(color, theme))
                ctx.textPosition = CGPoint(x: origin.x + o.x, y: origin.y + o.y)
                CTLineDraw(line, ctx)
                ctx.restoreGState()

            case let .glyph(id, size, o, color):
                // A MATH-table delimiter size variant, addressed by glyph ID.
                guard let sizedFont = font.ctFont(size: size) else { break }
                ctx.saveGState()
                ctx.setFillColor(cgColor(color, theme))
                // CTFontDrawGlyphs positions go through the context's TEXT
                // matrix, which still carries the translation a preceding
                // CTLineDraw left behind (and which saveGState does NOT
                // protect). Reset it or this glyph lands at the previous text
                // run's end position — the bug that shifted every variant
                // fence drawn after a glyph run.
                ctx.textMatrix = .identity
                var g = CGGlyph(id)
                var pos = CGPoint(x: origin.x + o.x, y: origin.y + o.y)
                CTFontDrawGlyphs(sizedFont, &g, &pos, 1, ctx)
                ctx.restoreGState()

            case let .rule(r, color):
                ctx.saveGState()
                ctx.setFillColor(cgColor(color, theme))
                ctx.fill(CGRect(x: origin.x + r.origin.x, y: origin.y + r.origin.y,
                                width: r.size.width, height: r.size.height))
                ctx.restoreGState()

            case .region:
                break   // hit-test metadata, not ink

            case let .stroke(path, width, cap, join, color):
                ctx.saveGState()
                ctx.setStrokeColor(cgColor(color, theme))
                ctx.setLineWidth(width)
                ctx.setLineCap(cap.cg)
                ctx.setLineJoin(join.cg)
                ctx.beginPath()
                for op in path {
                    switch op {
                    case .move(let p): ctx.move(to: CGPoint(x: origin.x + p.x, y: origin.y + p.y))
                    case .line(let p): ctx.addLine(to: CGPoint(x: origin.x + p.x, y: origin.y + p.y))
                    case let .quad(to, control):
                        ctx.addQuadCurve(to: CGPoint(x: origin.x + to.x, y: origin.y + to.y),
                                         control: CGPoint(x: origin.x + control.x, y: origin.y + control.y))
                    case let .cubic(to, c1, c2):
                        ctx.addCurve(to: CGPoint(x: origin.x + to.x, y: origin.y + to.y),
                                     control1: CGPoint(x: origin.x + c1.x, y: origin.y + c1.y),
                                     control2: CGPoint(x: origin.x + c2.x, y: origin.y + c2.y))
                    case .close: ctx.closePath()
                    }
                }
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
    }

    // MathColor is already sRGB components, so build the CGColor directly in the
    // sRGB space — identical on every platform (NSColor(srgbRed:) and
    // UIColor(red:) disagree: the latter is device/extended RGB).
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)

    private static func cgColor(_ color: MathColor?, _ theme: MathTheme) -> CGColor {
        guard let color else { return resolvedCGColor(theme.ink) }
        if let sRGB, let cg = CGColor(colorSpace: sRGB,
                                      components: [color.red, color.green, color.blue, color.alpha]) {
            return cg
        }
        return resolvedCGColor(theme.ink)
    }
}

private extension StrokeCap {
    var cg: CGLineCap { switch self { case .butt: return .butt; case .round: return .round; case .square: return .square } }
}
private extension StrokeJoin {
    var cg: CGLineJoin { switch self { case .miter: return .miter; case .round: return .round; case .bevel: return .bevel } }
}
#endif
