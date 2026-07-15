#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreText
import CoreGraphics
import VinculumLayout

/// The injected `MathScriptVariantProvider` backed by a font's parsed `ssty`
/// map: resolves a base glyph to its optically-redrawn script/scriptscript
/// variant and measures that variant by glyph ID — advance for spacing,
/// glyph bounding box for the ink extents scripts and accents attach to.
public enum CoreTextScriptVariantProvider {
    public static func make(font: MathFont = .latinModern) -> MathScriptVariantProvider? {
        guard let variants = font.scriptVariants, !variants.isEmpty else { return nil }
        return { glyph, size, level in
            guard level > 0,
                  let baseID = font.glyphID(for: glyph, size: size),
                  let variantID = variants.variant(for: baseID, level: level),
                  let ctFont = font.ctFont(size: size) else { return nil }
            var g = CGGlyph(variantID)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &g, &advance, 1)
            guard advance.width > 0 else { return nil }
            var rect = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &g, &rect, 1)
            // ascent/descent from the font's line metrics, matching how
            // CoreTextMeasurer measures a base glyph run (CTLine typographic
            // bounds); ink extents from the glyph box.
            let metrics = GlyphMetrics(
                width: advance.width,
                ascent: CTFontGetAscent(ctFont), descent: CTFontGetDescent(ctFont),
                inkAscent: max(0, rect.maxY), inkDescent: rect.minY)
            return ScriptGlyph(glyphID: variantID, metrics: metrics)
        }
    }
}
#endif
