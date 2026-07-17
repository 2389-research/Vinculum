// Linux verification of the platform-free DisplayList emitter (A0, #76), driven
// by the FreeType outliner — the engine Android will actually use.
#if canImport(SilicaCairo) && !canImport(AppKit) && !canImport(UIKit)
import XCTest
import Foundation
import Cairo
@testable import VinculumRender
@testable import VinculumLayout

/// Proves the emitter on the *other* backend: build a scene with FreeType,
/// emit its `DisplayList` via `FreeTypeOutliner`, rasterize the list straight to
/// PNG (`MathSilicaRenderer.png(for:)`), and check its ink signature against the
/// normal scene→PNG path (`renderPNG`). Both fill the SAME FreeType outlines, so
/// they must agree — the display list reproducing what the real Cairo backend
/// draws is exactly the "fully determines the picture" claim, on Linux.
final class MathDisplayListSilicaTests: XCTestCase {

    // Build the scene + display list from LaTeX, mirroring renderPNG so the two
    // sides compare the identical scene.
    private func displayList(_ latex: String, baseSize: CGFloat = 24) throws -> DisplayList {
        let (_, font) = try XCTUnwrap(MathSilicaRenderer.loadFont(resource: "latinmodern-math"))
        let node = MathParser.parse(latex)
        try XCTSkipUnless(MathParser.isFullySupported(node), "unsupported: \(latex)")
        let constants = MathSilicaRenderer.mathConstants(for: font) ?? .latinModern
        let engine = MathLayoutEngine(
            services: MathFontServices(measure: MathSilicaRenderer.freeTypeMeasurer(font: font),
                                       constants: constants),
            baseSize: baseSize * 1.15)
        let scene = engine.layout(node, display: true)
        return MathDisplayListRenderer.displayList(for: scene, outliner: FreeTypeOutliner.make(font: font))
    }

    // MARK: - Structure

    func testFractionEmitsARuleForTheBar() throws {
        let list = try displayList(#"\frac{a}{b}"#)
        XCTAssertTrue(list.ops.contains { if case .fillRect = $0 { return true }; return false },
                      "the fraction bar must be a fillRect")
    }

    func testGlyphsBecomeFilledOutlines() throws {
        let list = try displayList(#"x + y"#)
        XCTAssertTrue(list.ops.contains { if case .fillPath = $0 { return true }; return false })
    }

    /// The `.glyph(id:)` path through FreeType: a tall `\left(…\right)` swaps in a
    /// MATH-table size variant with no character spelling, outlined via
    /// `FreeTypeFont.outline`. It must render, not vanish.
    func testStretchyDelimiterRendersAsOutlines() throws {
        let tall = try displayList(#"\left( \frac{a}{\frac{b}{c}} \right)"#)
        let plain = try displayList(#"(x)"#)
        let tallFills = tall.ops.filter { if case .fillPath = $0 { return true }; return false }.count
        let plainFills = plain.ops.filter { if case .fillPath = $0 { return true }; return false }.count
        XCTAssertGreaterThan(tallFills, plainFills, "the size-variant fences add filled outlines")
        XCTAssertGreaterThan(tall.height, plain.height * 2, "the stretched fences must be tall")
    }

    // MARK: - Fidelity: the display list matches what the Cairo backend draws

    /// Direct pixel comparison, not a coarse ink signature — the two PNGs draw
    /// the SAME FreeType outlines through the SAME Cairo, so they're expected to
    /// be near-identical, and a per-pixel diff catches a thin feature (a missing
    /// 1px fraction bar) that a size-normalized grid dilutes away. (Learned:
    /// a 24×8 signature changed a dropped bar's cells by only one level, which
    /// an `abs > 1` tolerance ignored — the test couldn't see the bar at all.)
    func testDisplayListPNGMatchesSilicaRenderPNG() throws {
        for latex in [#"x^2"#, #"\frac{a}{b}"#, #"x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}"#,
                      #"\sum_{i=1}^{n} i^2"#, #"\left( \frac{a}{\frac{b}{c}} \right)"#] {
            let list = try displayList(latex)
            let listPNG = try XCTUnwrap(MathSilicaRenderer.png(for: list),
                                        "display list rasterized to nothing: \(latex)")
            let refPNG = try XCTUnwrap(MathSilicaRenderer.renderPNG(latex: latex, baseSize: 24, display: true),
                                       "renderPNG returned nil: \(latex)")
            let ratio = try pixelDiffRatio(listPNG, refPNG)
            XCTAssertLessThanOrEqual(ratio, 0.01,
                "\(String(format: "%.2f%%", ratio * 100)) of pixels differ — the display list does "
                + "not reproduce what the Cairo backend draws for \(latex)")
        }
    }

    /// Fraction of pixels whose darkest channel differs by more than a small AA
    /// margin. Both images are drawn identically, so a real match is well under
    /// 1%; a dropped element (bar, glyph, fence) pushes a whole band over it.
    private func pixelDiffRatio(_ pngA: Data, _ pngB: Data) throws -> Double {
        let a = try Cairo.Surface.Image(png: pngA), b = try Cairo.Surface.Image(png: pngB)
        XCTAssertEqual(a.width, b.width, "render widths diverged")
        XCTAssertEqual(a.height, b.height, "render heights diverged")
        let w = a.width, h = a.height
        let ab = try XCTUnwrap(a.data), bb = try XCTUnwrap(b.data)
        let sa = a.stride, sb = b.stride
        func darkest(_ d: Data, _ s: Int, _ x: Int, _ y: Int) -> Int {
            let o = y * s + x * 4; return min(Int(d[o]), Int(d[o + 1]), Int(d[o + 2]))
        }
        var bad = 0
        for y in 0..<h { for x in 0..<w where abs(darkest(ab, sa, x, y) - darkest(bb, sb, x, y)) > 24 {
            bad += 1
        } }
        return Double(bad) / Double(max(1, w * h))
    }
}
#endif
