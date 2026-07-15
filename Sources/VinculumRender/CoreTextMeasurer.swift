#if canImport(AppKit) || canImport(UIKit)
import Foundation
import CoreText
import CoreGraphics
import VinculumLayout

/// The CoreText implementation of layout's `MathTextMeasurer` seam: measures a
/// glyph run in the bundled math font (or the monospace fallback for
/// unsupported source), returning typographic bounds plus the ink extents that
/// drive accent placement. This is the only place layout touches CoreText.
public enum CoreTextMeasurer {

    /// A CoreText-backed measurer to feed `MathLayoutEngine`. The returned
    /// closure memoizes: because the parser emits one node per character, the
    /// same `(text, size, mono)` triple recurs constantly (an N×N matrix of
    /// identical entries re-measures each glyph N² times), so a shared cache
    /// turns those into dictionary hits. Deterministic, so cross-thread races
    /// only ever recompute the same value.
    public static func make(font: MathFont = .latinModern) -> MathTextMeasurer {
        { text, size, mono in measure(text, size, mono, font) }
    }

    private struct Key: Hashable { let font: String; let text: String; let size: CGFloat; let mono: Bool }
    nonisolated(unsafe) private static var cache: [Key: GlyphMetrics] = [:]
    private static let lock = NSLock()

    private static func measure(_ text: String, _ size: CGFloat, _ mono: Bool,
                                _ font: MathFont) -> GlyphMetrics {
        let key = Key(font: font.name, text: text, size: size, mono: mono)
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        // Compute outside the lock — CoreText is thread-safe and this is the
        // expensive part; a duplicate concurrent miss just recomputes the
        // identical value.
        let ctFont: CTFont
        if mono {
            ctFont = PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
        } else if let mathFont = font.ctFont(size: size) {
            ctFont = mathFont
        } else {
            ctFont = PlatformFont.systemFont(ofSize: size) as CTFont
        }
        let attributed = NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: ctFont])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let ink = CTLineGetImageBounds(line, nil)
        let metrics = GlyphMetrics(width: width, ascent: ascent, descent: descent,
                                   inkAscent: min(ascent, max(0, ink.maxY)), inkDescent: ink.minY)

        lock.lock()
        if cache.count > 8192 { cache.removeAll(keepingCapacity: true) } // defensive bound
        cache[key] = metrics
        lock.unlock()
        return metrics
    }
}
#endif
