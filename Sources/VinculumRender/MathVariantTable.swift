#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreText
import CoreGraphics
import VinculumLayout

/// Serves a font's `MathVariants` data (size-variant ladders + glyph
/// assemblies) to layout through the delimiter provider seams. Stretchy
/// delimiters try a purpose-drawn size variant first, then an assembly of
/// parts, and only then fall back to continuous scaling.
enum MathVariantTable {

    private static func construction(for baseGlyph: String, size: CGFloat, font: MathFont)
        -> (MathVariantsData.Construction, CTFont)? {
        guard let data = font.variantsData,
              let ctFont = font.ctFont(size: size),
              let baseID = font.glyphID(for: baseGlyph, size: size),
              let con = data.vertical[baseID] else { return nil }
        return (con, ctFont)
    }

    /// The smallest vertical size variant of `baseGlyph` at point `size`
    /// whose height reaches `minHeight` (shortfall heuristic applied), or nil.
    static func shape(for baseGlyph: String, minHeight: CGFloat, size: CGFloat,
                      font: MathFont) -> DelimiterShape? {
        guard let (con, ctFont) = construction(for: baseGlyph, size: size, font: font),
              let v = con.bestVariant(forTarget: minHeight / size) else { return nil }
        var glyph = CGGlyph(v.glyphID)
        var rect = CGRect.zero, adv = CGSize.zero
        CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyph, &rect, 1)
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &adv, 1)
        let width = adv.width > 0 ? adv.width : rect.maxX
        let metrics = GlyphMetrics(width: width,
                                   ascent: max(0, rect.maxY), descent: max(0, -rect.minY),
                                   inkAscent: max(0, rect.maxY), inkDescent: rect.minY)
        guard metrics.ascent + metrics.descent > 0, width > 0 else { return nil }
        return DelimiterShape(glyphID: v.glyphID, metrics: metrics)
    }

    /// An assembled column of font parts reaching `minHeight`, or nil when
    /// the font provides no assembly for this glyph. Part glyphs in math
    /// fonts put their ink exactly on [0, fullAdvance] above the baseline,
    /// so draw offsets are the solved offsets directly.
    static func assembly(for baseGlyph: String, minHeight: CGFloat, size: CGFloat,
                         font: MathFont) -> DelimiterAssembly? {
        guard let data = font.variantsData,
              let (con, ctFont) = construction(for: baseGlyph, size: size, font: font),
              let asm = con.assembly,
              let solved = MathAssemblySolver.solve(asm, minOverlap: data.minConnectorOverlap,
                                                    target: minHeight / size) else { return nil }
        var width: CGFloat = 0
        for p in solved.placements {
            var glyph = CGGlyph(p.glyphID)
            var adv = CGSize.zero
            CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &adv, 1)
            width = max(width, adv.width)
        }
        guard width > 0 else { return nil }
        let placements = solved.placements.map {
            MathAssemblySolver.Placement(glyphID: $0.glyphID, offset: $0.offset * size)
        }
        return DelimiterAssembly(placements: placements, width: width,
                                 height: solved.total * size)
    }

    /// The widest HORIZONTAL variant of a combining accent not exceeding
    /// `maxWidth` (TeX Rule 12's successor walk). Ink located via `inkLeft`
    /// because combining marks draw behind their origin.
    static func wideAccent(for accentGlyph: String, maxWidth: CGFloat, size: CGFloat,
                           font: MathFont) -> DelimiterShape? {
        guard let ctFont = font.ctFont(size: size),
              let baseID = font.glyphID(for: accentGlyph, size: size) else { return nil }
        // Widest drawn cut not exceeding maxWidth; the BASE glyph when none
        // fits (or the mark has no ladder). Returning the base — with exact
        // ink metrics — matters beyond stretching: a lone combining mark
        // drawn as a *string* gets shaping-dependent ink placement, so
        // point accents like \vec route through here with maxWidth 0.
        var chosenID = baseID
        if let con = font.variantsData?.horizontal[baseID] {
            for v in con.variants where v.advance * size <= maxWidth { chosenID = v.glyphID }
        }
        var glyph = CGGlyph(chosenID)
        var rect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyph, &rect, 1)
        guard rect.width > 0 else { return nil }
        let metrics = GlyphMetrics(width: rect.width,
                                   ascent: max(0, rect.maxY), descent: max(0, -rect.minY),
                                   inkAscent: max(0, rect.maxY), inkDescent: rect.minY,
                                   inkLeft: rect.minX)
        return DelimiterShape(glyphID: chosenID, metrics: metrics)
    }
}

/// The injected `MathDelimiterProvider` backed by `MathVariantTable`.
public enum CoreTextDelimiterProvider {
    public static func make(font: MathFont = .latinModern) -> MathDelimiterProvider {
        { glyph, minHeight, size in
            MathVariantTable.shape(for: glyph, minHeight: minHeight, size: size, font: font)
        }
    }

    /// The assembly companion: font parts for heights beyond the largest
    /// size variant.
    public static func makeAssembly(font: MathFont = .latinModern) -> MathDelimiterAssemblyProvider {
        { glyph, minHeight, size in
            MathVariantTable.assembly(for: glyph, minHeight: minHeight, size: size, font: font)
        }
    }

    /// Horizontal width variants for stretchy accents (\widehat family).
    public static func makeAccentVariants(font: MathFont = .latinModern) -> MathAccentVariantProvider {
        { glyph, maxWidth, size in
            MathVariantTable.wideAccent(for: glyph, maxWidth: maxWidth, size: size, font: font)
        }
    }
}
#endif
