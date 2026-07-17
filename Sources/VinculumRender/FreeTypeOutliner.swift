// A `MathOutliner` (from VinculumLayout) backed by FreeType — the font
// capability the platform-free `DisplayList` emitter needs on Linux and, in
// time, on Android. The sibling of `CoreTextOutliner`: same seam, different
// engine, and the SAME engine that measured the scene, so outlines land exactly
// where layout placed them (the seam-parity law, #62). See docs/ANDROID.md.
#if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
import Foundation
import VinculumLayout

enum FreeTypeOutliner {
    // Internal: `FreeTypeFont` is internal, and every consumer (the renderer,
    // the eventual C ABI) lives in this module.
    static func make(font: FreeTypeFont) -> MathOutliner {
        MathOutliner(
            glyphRun: { text, size, _ in
                // `mono` is ignored: the unsupported-source monospace fallback
                // never reaches a rasterizer (renderPNG gates on
                // isFullySupported), so a scene fed here carries only math-font
                // runs. Kept in the signature to match the seam.
                var ops: [PathOp] = []
                var penX: CGFloat = 0
                for scalar in text.unicodeScalars {
                    let gid = font.glyphIndex(scalar)
                    if let g = font.outline(glyph: gid, size: size) {
                        ops += g.map { $0.offset(by: CGPoint(x: penX, y: 0)) }
                    }
                    penX += font.advanceEm(glyph: gid) * size
                }
                return ops
            },
            variantGlyph: { id, size in font.outline(glyph: id, size: size) }
        )
    }
}
#endif
