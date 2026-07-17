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
            let ops = CoreTextOutliner.pathOps(from: path)
            return ops.isEmpty ? nil : ops
        }
    }
}

/// A full `MathOutliner` backed by CoreText — the font capability the
/// `DisplayList` emitter needs (`docs/ANDROID.md`), used to verify the
/// platform-free emitter on Apple before an Android toolchain exists.
///
/// The glyph-run path is built through `CTLine`, the **same** machinery
/// `CoreTextMeasurer` measures with, so the outlines land exactly where layout
/// placed the run (no seam, #62) and astral math-alphanumerics shape correctly.
public enum CoreTextOutliner {
    public static func make(font: MathFont = .latinModern) -> MathOutliner {
        MathOutliner(
            glyphRun: { text, size, mono in
                let ctFont: CTFont
                if mono {
                    ctFont = PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
                } else if let f = font.ctFont(size: size) {
                    ctFont = f
                } else {
                    ctFont = PlatformFont.systemFont(ofSize: size) as CTFont
                }
                return runOutline(text, ctFont: ctFont)
            },
            variantGlyph: CoreTextGlyphOutlineProvider.make(font: font)
        )
    }

    /// Every glyph in the run, outlined and placed at its `CTLine` position
    /// (baseline-relative, y-up — the scene convention).
    private static func runOutline(_ text: String, ctFont: CTFont) -> [PathOp] {
        guard !text.isEmpty else { return [] }
        let attributed = NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: ctFont])
        let line = CTLineCreateWithAttributedString(attributed)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return [] }

        var result: [PathOp] = []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            // The run's actual font — CoreText may substitute for a missing glyph.
            let attrs = CTRunGetAttributes(run) as NSDictionary
            guard let runFontRaw = attrs[kCTFontAttributeName as String] else { continue }
            let runFont = runFontRaw as! CTFont

            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRangeMake(0, count), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, count), &positions)

            for i in 0..<count {
                guard let path = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                result += pathOps(from: path).map { $0.offset(by: positions[i]) }
            }
        }
        return result
    }

    /// `CGPath` → `PathOp`s. CoreGraphics glyph paths are already y-up with the
    /// origin on the baseline — the scene's convention — so points pass through
    /// unchanged.
    static func pathOps(from path: CGPath) -> [PathOp] {
        var ops: [PathOp] = []
        path.applyWithBlock { elementPtr in
            let e = elementPtr.pointee
            let p = e.points
            switch e.type {
            case .moveToPoint:    ops.append(.move(p[0]))
            case .addLineToPoint: ops.append(.line(p[0]))
            case .addQuadCurveToPoint: ops.append(.quad(to: p[1], control: p[0]))
            case .addCurveToPoint: ops.append(.cubic(to: p[2], control1: p[0], control2: p[1]))
            case .closeSubpath:   ops.append(.close)
            @unknown default:     break
            }
        }
        return ops
    }
}
#endif
