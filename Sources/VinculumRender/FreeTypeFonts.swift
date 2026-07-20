// FreeType font loading + the FreeType-backed measurer and MATH constants — the
// FreeType TIER, with no Cairo dependency. Gated on `canImport(CFreetypeShim)`
// (not SilicaCairo), so it is available wherever FreeType is: Linux under either
// the `FreeTypeRaster` or `LinuxRaster` trait, and — the point of the split —
// Android, which has FreeType but no Cairo. The Cairo PNG backend
// (`MathSilicaRenderer`) builds on top of this tier; the Android C ABI
// (`VinculumWireC`) uses this tier directly, no Cairo involved.
#if canImport(CFreetypeShim) && !canImport(AppKit) && !canImport(UIKit)
import Foundation
import VinculumLayout

/// Loads the bundled MATH `.otf` fonts through FreeType and exposes the two
/// things the layout engine's seams need from them: a measurer (glyph metrics +
/// ink extents) and the font's own MATH-table constants. Shared by the Cairo
/// PNG renderer, the Android C ABI, and the tests, so they all exercise one
/// load path.
public enum FreeTypeFonts {

    static let resources = ["latinmodern-math", "texgyretermes-math",
                            "texgyrepagella-math", "stixtwo-math", "firamath"]

    /// An explicit directory to load the bundled `.otf`s from, bypassing
    /// `Bundle.module`. This is the **Android** path: SwiftPM's resource-bundle
    /// accessor (`Bundle.module`) traps with a fatalError inside an APK — there is
    /// no `.bundle` directory next to the `.so` — so the host ships the fonts as
    /// APK assets, extracts them once, and hands the directory here via
    /// `vinculum_set_font_dir`. On Apple/Linux it stays nil and `Bundle.module`
    /// works as before, so nothing changes there.
    nonisolated(unsafe) private static var _fontDirectory: String?
    private static let fontDirLock = NSLock()
    static var fontDirectory: String? {
        get { fontDirLock.lock(); defer { fontDirLock.unlock() }; return _fontDirectory }
        set { fontDirLock.lock(); _fontDirectory = newValue; fontDirLock.unlock() }
    }

    /// The font's OWN MATH constants, or nil if it carries no MATH table.
    ///
    /// `MathTableParser` parses the MATH TABLE's bytes, never a font file: handing
    /// it the whole `.otf` fails the version guard (bytes 0-3 are the sfnt tag —
    /// 'OTTO' for our CFF fonts), which silently substituted Latin Modern's
    /// metrics for every bundled font (#1). The renderer and the tests go through
    /// here, so a regression to the font-file form fails the tests.
    static func mathConstants(for font: FreeTypeFont) -> MathFontConstants? {
        font.sfntTable(tag: FreeTypeFont.mathTableTag)
            .flatMap { MathTableParser.constants(from: $0, unitsPerEm: Int(font.unitsPerEm)) }
    }

    /// A bundled font's raw bytes plus its FreeType face, or nil if the resource
    /// isn't one of ours or can't be read. Shared with the font-constants tests
    /// so they exercise exactly the load path the renderer uses.
    static func loadFont(resource: String) -> (otf: Data, font: FreeTypeFont)? {
        guard resources.contains(resource) else { return nil }
        // A set fontDirectory wins and Bundle.module is never touched — the whole
        // point on Android, where merely evaluating the `Bundle.module` accessor
        // traps. Otherwise fall back to the SwiftPM resource bundle (Apple/Linux).
        let otf: Data
        if let dir = fontDirectory {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(resource).otf")
            guard let data = try? Data(contentsOf: url) else { return nil }
            otf = data
        } else {
            guard let url = Bundle.module.url(forResource: resource, withExtension: "otf"),
                  let data = try? Data(contentsOf: url) else { return nil }
            otf = data
        }
        guard let font = FreeTypeFont(bytes: otf) else { return nil }
        return (otf, font)
    }

    /// The FreeType `MathTextMeasurer` for `font` — glyph metrics + ink extents
    /// from the same face that outlines the glyphs (no #62 seam). Shared with the
    /// display-list tests so they build the exact scene `renderPNG` does.
    static func freeTypeMeasurer(font: FreeTypeFont) -> MathTextMeasurer {
        { text, size, _ in
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
    }
}
#endif
