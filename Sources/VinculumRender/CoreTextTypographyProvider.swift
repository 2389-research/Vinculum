#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreText
import VinculumLayout

/// The injected `MathGlyphTypographyProvider` backed by a font's parsed
/// `MathGlyphInfo`: resolves the rendered glyph string to a glyph ID via
/// CoreText, then scales the em-relative table values to the queried point
/// size. Returns nil for glyphs the table doesn't cover, so layout falls
/// back to neutral defaults.
public enum CoreTextTypographyProvider {

    public static func make(font: MathFont = .latinModern) -> MathGlyphTypographyProvider {
        { glyph, size in
            guard let info = font.glyphInfo,
                  let gid = font.glyphID(for: glyph, size: size) else { return nil }
            let italic = info.italicsCorrection[gid]
            let accent = info.topAccentAttachment[gid]
            let kerns = info.kerns[gid]
            guard italic != nil || accent != nil || kerns != nil else { return nil }
            return GlyphTypography(
                italicsCorrection: (italic ?? 0) * size,
                topAccentAttachment: accent.map { $0 * size },
                kernTopRight: kerns?.topRight?.scaled(by: size),
                kernBottomRight: kerns?.bottomRight?.scaled(by: size))
        }
    }
}
#endif
