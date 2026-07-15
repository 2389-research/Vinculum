#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreText
import CoreGraphics
import VinculumLayout

/// A `GlyphOutlineProvider` backed by CoreText: turns a glyph ID into its
/// filled outline (`CTFontCreatePathForGlyph`) as `PathOp`s in scene
/// coordinates. Lets `MathSVGRenderer` draw `.glyph(id:)` elements (delimiter
/// size variants and `ssty` optical scripts) that have no character spelling.
public enum CoreTextGlyphOutlineProvider {
    public static func make(font: MathFont = .latinModern) -> GlyphOutlineProvider {
        { glyphID, size in
            guard let ctFont = font.ctFont(size: size),
                  let path = CTFontCreatePathForGlyph(ctFont, CGGlyph(glyphID), nil) else { return nil }
            // CoreGraphics glyph paths are already y-up with the origin at the
            // glyph baseline — the scene's convention — so points pass through
            // unchanged.
            var ops: [PathOp] = []
            path.applyWithBlock { elementPtr in
                let e = elementPtr.pointee
                let p = e.points
                switch e.type {
                case .moveToPoint:    ops.append(.move(p[0]))
                case .addLineToPoint: ops.append(.line(p[0]))
                case .addQuadCurveToPoint:
                    ops.append(.quad(to: p[1], control: p[0]))
                case .addCurveToPoint:
                    ops.append(.cubic(to: p[2], control1: p[0], control2: p[1]))
                case .closeSubpath:   ops.append(.close)
                @unknown default:     break
                }
            }
            return ops.isEmpty ? nil : ops
        }
    }
}
#endif
