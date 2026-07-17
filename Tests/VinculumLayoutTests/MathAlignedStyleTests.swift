import XCTest
import Foundation
@testable import VinculumLayout

/// TeX fixes each grid environment's cell style; it is NOT inherited from the
/// surrounding context.
///
/// amsmath sets `align`/`aligned`/`gather`/`split` cells in **display** style
/// (always, forced), while `matrix`/`array`/`cases` cells are **text** style
/// regardless of what surrounds them. `matrixBox` hardcoded `.text` for all of
/// them, so a `\sum`/`\int` inside an `aligned` block rendered with text-size,
/// side-set limits where real amsmath produces display-size stacked ones (#21).
///
/// That "fixed, not inherited" fact is why the ambient `MathStyle` isn't
/// threaded into `matrixBox`: it would be the wrong input. The cell style is a
/// function of the environment alone.
final class MathAlignedStyleTests: XCTestCase {

    private let mock = standardMockMeasurer

    /// Serves a big-∑ variant (gid 42) only at display size — so "did this cell
    /// lay out in display style?" becomes a single binary observation.
    private func operatorProvider() -> MathDelimiterProvider {
        { glyph, minHeight, size in
            guard glyph == "∑" || glyph == "∫", minHeight >= size * 1.3 else { return nil }
            return DelimiterShape(glyphID: 42, metrics: GlyphMetrics(
                width: size * 1.4, ascent: size * 1.0, descent: size * 0.4,
                inkAscent: size * 1.0, inkDescent: -size * 0.4))
        }
    }

    private func usesDisplayVariant(_ latex: String, display: Bool = true) -> Bool {
        let engine = MathLayoutEngine(services: .init(measure: mock, delimiters: operatorProvider()),
                                      baseSize: 10)
        let scene = engine.layout(MathParser.parse(latex), display: display)
        return scene.elements.contains { element in
            if case .glyph(42, _, _, _) = element { return true }
            return false
        }
    }

    // MARK: - aligned family: display style

    func testAlignedCellsUseDisplayStyle() {
        XCTAssertTrue(usesDisplayVariant(#"\begin{aligned} S &= \sum_{i=1}^n a_i \end{aligned}"#),
                      "amsmath sets aligned cells in display style — a \\sum there must use "
                      + "the display-size variant with stacked limits, not inline side-set ones")
    }

    func testAlignFamilyAllUseDisplayStyle() {
        // All of these parse to MathMatrixStyle.aligned and are display in amsmath.
        for env in ["align", "aligned", "gather", "gathered", "split"] {
            XCTAssertTrue(usesDisplayVariant("\\begin{\(env)} \\sum_{i=1}^n a_i \\end{\(env)}"),
                          "\(env) cells are display style in amsmath")
        }
    }

    /// The style is FORCED, not inherited: an `aligned` block is display style
    /// even when it appears inline.
    func testAlignedIsDisplayEvenWhenInline() {
        XCTAssertTrue(usesDisplayVariant(#"\begin{aligned} \sum_{i=1}^n a_i \end{aligned}"#,
                                         display: false),
                      "aligned forces display style — it does not inherit the inline context")
    }

    // MARK: - matrix family stays text (the false-positive guard)

    /// The counter-half, and the reason this fix is narrow. The original report
    /// framed it as "cells should inherit the surrounding style", which would
    /// have ALSO promoted these to display and been TeX-incorrect. If this ever
    /// goes red, the fix has overreached.
    func testMatrixArrayAndCasesStayTextStyle() {
        for latex in [#"\begin{pmatrix} \sum_{i=1}^n a_i \end{pmatrix}"#,
                      #"\begin{matrix} \sum_{i=1}^n a_i \end{matrix}"#,
                      #"\begin{array}{c} \sum_{i=1}^n a_i \end{array}"#,
                      #"\begin{cases} \sum_{i=1}^n a_i & x > 0 \end{cases}"#] {
            XCTAssertFalse(usesDisplayVariant(latex),
                           "matrix/array/cases cells are TEXT style in TeX regardless of "
                           + "surroundings — promoting them to display is incorrect: \(latex)")
        }
    }

    func testSubstackCellsStayTight() {
        // The operator must be INSIDE the substack. `\sum_{\substack{…}}` would
        // observe the OUTER sum, which is display style regardless — the probe
        // would then report true no matter what the cells did, and the test
        // would be dead (it failed identically before and after the fix).
        XCTAssertFalse(usesDisplayVariant(#"x_{\substack{\sum_{i=1}^n a \\ j=2}}"#),
                       "substack cells must not be promoted to display style")
    }
}
